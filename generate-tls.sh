#!/bin/bash

# Based on:
# https://www.baeldung.com/openssl-self-signed-cert
# https://stackoverflow.com/questions/906402/how-to-import-an-existing-x-509-certificate-and-private-key-in-java-keystore-to
# https://stackoverflow.com/questions/14375235/how-to-list-the-certificates-stored-in-a-pkcs12-keystore-with-keytool

mkdir -p ${PWD}/certs
CA_PATH=${PWD}/certs




### Helper Functions

create_ca() {
    echo
    echo "Create our own Root CA"
    openssl req \
        -x509 -sha256 -days 1825 -newkey rsa:2048 \
        -keyout ${CA_PATH}/rootCA.key -out ${CA_PATH}/rootCA.crt \
        -passout pass:conduktor \
        -subj '/CN=rootCA/OU=TEST/O=CONDUKTOR/L=LONDON/C=UK'
}




clean_certificates() {
    local DIR="${CA_PATH}"
    echo "Cleaning up directory $DIR"
    (cd "${DIR}" && rm -f *.crt *.csr *_creds *.jks *.srl *.key *.pem *.der *.p12 *.log *.ext)
}




create_certificate() {

    # Get subject alternate names (SANs) from arguments
    declare subject_alt_names
    i=0
    for san in "$@"
    do
        subject_alt_names+=",DNS.$i:${san}"
        ((i++))
    done
    # get rid of leading comma
    subject_alt_names=${subject_alt_names:1}

    echo
    echo "Generating ext file for SANs"
    echo "$subject_alt_names"

    cat <<EOF > ${CA_PATH}/$1.san.ext
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
req_extensions = v3_req
prompt = no
[req_distinguished_name]
CN = $1
[v3_req]
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = $subject_alt_names
EOF


    echo
    echo "Generate Private Key"
    openssl genrsa -des3 -passout pass:conduktor -out ${CA_PATH}/$1.key 2048

    echo
    echo "Generate unencrypted Private Key for kubectl secret"
    openssl rsa -in ${CA_PATH}/$1.key -out ${CA_PATH}/$1.unencrypted.key -passin pass:conduktor

    echo
    echo "Generate certificate signing request - This would have been sent to the CA"
    openssl req \
        -key ${CA_PATH}/$1.key \
        -new -out ${CA_PATH}/$1.csr \
        -passin pass:conduktor \
        -subj "/CN=${1}/OU=TEST/O=CONDUKTOR/L=LONDON/C=UK" \
        -reqexts v3_req -config ${CA_PATH}/$1.san.ext


    echo
    echo "Generate Certificate, signed by Root CA with SAN"
    openssl x509 -req \
        -CA ${CA_PATH}/rootCA.crt -CAkey ${CA_PATH}/rootCA.key \
        -in ${CA_PATH}/$1.csr \
        -out ${CA_PATH}/$1.crt \
        -days 365 -CAcreateserial \
        -extensions v3_req -extfile ${CA_PATH}/$1.san.ext \
        -passin pass:conduktor

    echo
    echo "Show the content of the signed Certificate"
    openssl x509 -text -noout -in ${CA_PATH}/$1.crt -passin pass:conduktor

    echo
    echo "Creating full certificate chain"
    cat ${CA_PATH}/$1.crt ${CA_PATH}/rootCA.crt > ${CA_PATH}/$1.fullchain.crt


    # IMPORTANT: Creating the keystore this way will require the key password and keystore password to be the same
    echo
    echo "Generate a PKCS12 Keystore with alias $1"
    openssl pkcs12 -inkey ${CA_PATH}/$1.key -in ${CA_PATH}/$1.fullchain.crt -export -out ${CA_PATH}/$1.p12 -passin pass:conduktor -passout pass:conduktor -name $1

    echo
    echo "Show the content of the PKCS12 Keystore from the point of view of Java keytool, to see the alias"
    keytool -list -v -keystore ${CA_PATH}/$1.p12 -storepass conduktor -storetype PKCS12

    echo
    echo "Generate a JKS Keystore from PKCS12 Keystore"
    keytool \
        -importkeystore \
        -deststorepass conduktor -destkeypass conduktor \
        -destkeystore ${CA_PATH}/$1.keystore.jks \
        -deststoretype PKCS12 -srckeystore ${CA_PATH}/$1.p12 \
        -srcstoretype PKCS12 \
        -srcstorepass conduktor \
        -alias $1

    echo
    echo "Show the content of the JKS Keystore"
    keytool -list -v -keystore ${CA_PATH}/$1.keystore.jks -storepass conduktor

}

create_truststore() {
    keytool -noprompt \
        -keystore ${CA_PATH}/truststore.jks \
        -alias rootCA \
        -import -file ${CA_PATH}/rootCA.crt \
        -storepass conduktor \
        -keypass conduktor
}




### Main function

clean_certificates
create_ca
create_truststore

create_certificate kafka \
    franz-kafka.conduktor.svc.cluster.local \
    *.franz-kafka-controller-headless.conduktor.svc.cluster.local \
    *.franz-kafka-broker-headless.conduktor.svc.cluster.local

create_certificate gateway.conduktor.k8s.orb.local \
    brokermain0-gateway.conduktor.k8s.orb.local \
    brokermain1-gateway.conduktor.k8s.orb.local \
    brokermain2-gateway.conduktor.k8s.orb.local \
    brokermain3-gateway.conduktor.k8s.orb.local \
    brokermain4-gateway.conduktor.k8s.orb.local \
    brokermain5-gateway.conduktor.k8s.orb.local \
    brokermain100-gateway.conduktor.k8s.orb.local \
    brokermain101-gateway.conduktor.k8s.orb.local \
    brokermain102-gateway.conduktor.k8s.orb.local \
    brokermain103-gateway.conduktor.k8s.orb.local \
    brokermain104-gateway.conduktor.k8s.orb.local \
    brokermain105-gateway.conduktor.k8s.orb.local

create_certificate console.conduktor.k8s.orb.local

cp ${CA_PATH}/truststore.jks ${CA_PATH}/kafka.truststore.jks 