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
    -passout pass:changeit \
    -subj '/CN=ca1.test.conduktor.io/OU=TEST/O=CONDUKTOR/L=LONDON/C=UK'
}

clean_certificates() {
    # Cleanup files
    local DIR="${CA_PATH}"
    echo "Cleaning up directory $DIR"
    (cd "${DIR}" && rm -f *.crt *.csr *_creds *.jks *.srl *.key *.pem *.der *.p12 *.log)
    (cd "${DIR}" && rm -fr keypair/)
}

create_certificate() {

# Get subject alternate names from arguments
declare -a subject_alt_names
for i in "$@"
do
    subject_alt_names+=($i)
done

echo
echo "Generate Private Key"
openssl genrsa -des3 -passout pass:changeit -out $1.key 2048

echo
echo "Generate certificate signing request - This would have been sent to the CA"
openssl req \
    -key $1.key \
    -new -out $1.csr \
    -passin pass:changeit \
    -subj "/CN=${1}/OU=TEST/O=CONDUKTOR/L=LONDON/C=UK"

cat <<END > $1.san.ext
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no
[req_distinguished_name]
CN = $user
[v3_req]
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = $san_for_config
END

echo
echo "Generate Certificate, signed by Root CA with SAN"
openssl x509 -req -CA rootCA.crt -CAkey rootCA.key -in domain.csr -out domain.crt -days 365 -CAcreateserial -extfile san-extension -passin pass:changeit

echo
echo "Show the content of the signed Certificate"
openssl x509 -text -noout -in domain.crt -passin pass:changeit

echo
echo Generate a PKCS12 Keystore with alias 'domainalias'
openssl pkcs12 -inkey domain.key -in domain.crt -export -out domain.p12 -passin pass:changeit -passout pass:changeit -name domainalias

echo
echo "Show the content of the PKCS12 Keystore from the point of view of Java keytool, to see the alias"
keytool -list -v -keystore domain.p12 -storepass changeit -storetype PKCS12

echo
echo "Generate a JKS Keystore from PKCS12 Keystore (note the alias '1')"
keytool -importkeystore -deststorepass changeit -destkeypass changeit -destkeystore domain.keystore.jks -deststoretype JKS -srckeystore domain.p12 -srcstoretype PKCS12 -srcstorepass changeit -alias domainalias

echo
echo "Show the content of the JKS Keystore"
keytool -list -v -keystore domain.keystore.jks -storepass changeit

}

create_truststore() {
keytool -noprompt \
    -keystore ${CA_PATH}/truststore.jks \
    -alias snakeoil-caroot \
    -import -file ${CA_PATH}/rootCA.crt \
    -storepass conduktor \
    -keypass conduktor
}


### Main function

clean_certificates
create_ca
create_truststore
echo hello