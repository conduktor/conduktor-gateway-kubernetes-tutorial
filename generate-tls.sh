#!/bin/bash

mkdir -p ${PWD}/certs
CA_PATH=${PWD}/certs

#################################################
## Helper functions
#################################################

create_certificate_per_user() {

    local user=$1

    shift
    declare -a subject_alt_names
    subject_alt_names+=("$user")

    # additional alt names if any
    for additional_san in "$@"
    do 
        subject_alt_names+=($additional_san)
    done

    local san_for_csr="SAN="
    local san_for_config=""
    local i=0
    for san in "${subject_alt_names[@]}"
    do
        if [[ $i -gt 0 ]]; then
            san_for_csr+=","
            san_for_config+=","
        fi
        san_for_csr+="dns:${san}"
        san_for_config+="DNS.$i:${san}"
        ((i++))
    done

    local log_file="certs-create-$user.log"

    echo "Generating certificate with following SAN: ${san_for_config}" >> $log_file 2>&1

    # Create host keystore
    keytool -genkey -noprompt \
                -alias $user \
                -dname "CN=$user,OU=TEST,O=CONDUKTOR,L=LONDON,C=UK" \
                            -ext "$san_for_csr" \
                -keystore $user.keystore.jks \
                -keyalg RSA \
                -storepass conduktor \
                -keypass conduktor \
                -storetype pkcs12 &> $log_file

    # Create the certificate signing request (CSR)
    keytool -keystore $user.keystore.jks -alias $user -certreq -file $user.csr -storepass conduktor -keypass conduktor -ext "$san_for_csr" >> $log_file 2>&1
    #openssl req -in $user.csr -text -noout

    echo "Sign the host certificate with the certificate authority (CA)"
    # Set a random serial number (avoid problems from using '-CAcreateserial' when parallelizing certificate generation)
    CERT_SERIAL=$(awk -v seed="$RANDOM" 'BEGIN { srand(seed); printf("0x%.4x%.4x%.4x%.4x\n", rand()*65535 + 1, rand()*65535 + 1, rand()*65535 + 1, rand()*65535 + 1) }')
    openssl x509 -req -CA ${CA_PATH}/snakeoil-ca-1.crt -CAkey ${CA_PATH}/snakeoil-ca-1.key -in $user.csr -out $user-ca1-signed.crt -sha256 -days 365 -set_serial ${CERT_SERIAL} -passin pass:conduktor -extensions v3_req -extfile <(cat <<EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no
[req_distinguished_name]
CN = $user
[v3_req]
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = $san_for_config
EOF
) >> $log_file 2>&1
    #openssl x509 -noout -text -in $user-ca1-signed.crt

    echo "Sign and import the CA cert into the keystore"
    keytool -noprompt -keystore $user.keystore.jks -alias snakeoil-caroot -import -file ${CA_PATH}/snakeoil-ca-1.crt -storepass conduktor -keypass conduktor >> $log_file 2>&1
    #keytool -list -v -keystore $user.keystore.jks -storepass conduktor

    # Sign and import the host certificate into the keystore
    keytool -noprompt -keystore $user.keystore.jks -alias $user -import -file $user-ca1-signed.crt -storepass conduktor -keypass conduktor -ext "SAN=dns:$user,dns:localhost" >> $log_file 2>&1
    #keytool -list -v -keystore $user.keystore.jks -storepass conduktor

    echo "Create truststore and import the CA cert"
    # TODO: remove this and use 'global' truststore instead
    keytool -noprompt -keystore $user.truststore.jks -alias snakeoil-caroot -import -file ${CA_PATH}/snakeoil-ca-1.crt -storepass conduktor -keypass conduktor >> $log_file 2>&1

    # Save creds
    echo "conduktor" > ${user}_sslkey_creds
    echo "conduktor" > ${user}_keystore_creds
    echo "conduktor" > ${user}_truststore_creds

    # Create pem files and keys used for Schema Registry HTTPS testing
    #   openssl x509 -noout -modulus -in client.certificate.pem | openssl md5
    #   openssl rsa -noout -modulus -in client.key | openssl md5 
    #   echo "GET /" | openssl s_client -connect localhost:8085/subjects -cert client.certificate.pem -key client.key -tls1
    keytool -export -alias $user -file $user.der -keystore $user.keystore.jks -storepass conduktor 2>> $log_file
    openssl x509 -inform der -in $user.der -out $user.certificate.pem 2>> $log_file
    keytool -importkeystore -srckeystore $user.keystore.jks -destkeystore $user.keystore.p12 -deststoretype PKCS12 -deststorepass conduktor -srcstorepass conduktor -noprompt 2>> $log_file 
    openssl pkcs12 -in $user.keystore.p12 -nodes -nocerts -out $user.key -passin pass:conduktor 2>> $log_file

}

clean_certificates() {
    # Cleanup files
    local DIR="${CA_PATH}"
    echo $DIR
    (cd "${DIR}" && rm -f *.crt *.csr *_creds *.jks *.srl *.key *.pem *.der *.p12 *.log)
    (cd "${DIR}" && rm -fr keypair/)
}

generate_ca_cert() {
    echo "Generate CA key"
    (cd $CA_PATH && openssl req -new -x509 -keyout snakeoil-ca-1.key -out snakeoil-ca-1.crt -days 365 -subj '/CN=ca1.test.conduktor.io/OU=TEST/O=CONDUKTOR/L=LONDON/C=UK' -passin pass:conduktor -passout pass:conduktor)
}

generate_certificate() {
    local user=$1
    shift
    
    (cd $CA_PATH && create_certificate_per_user $user $@)
    echo "Created certificates for $user"    
}

generate_truststore() {
    echo "generating trust store"
   (cd $CA_PATH && keytool -noprompt -keystore truststore.jks -alias snakeoil-caroot -import -file ${CA_PATH}/snakeoil-ca-1.crt -storepass conduktor -keypass conduktor) 
}


#################################################
## Main
#################################################


clean_certificates
generate_ca_cert
generate_certificate kafka franz-kafka.conduktor.svc.cluster.local *.franz-kafka-controller-headless.conduktor.svc.cluster.local
generate_certificate gateway.conduktor.k8s.orb.local *.conduktor.k8s.orb.local
