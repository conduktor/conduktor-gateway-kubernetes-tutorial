pushd certs

keytool -genkey -noprompt \
                -alias gateway \
                -dname "CN=*.conduktor.k8s.orb.local,OU=TEST,O=CONDUKTOR,L=LONDON,C=UK" \
                -keystore conduktor.k8s.orb.local.keystore.jks \
                -keyalg RSA \
                -storepass conduktor \
                -keypass conduktor \
                -storetype pkcs12



keytool -keystore conduktor.k8s.orb.local.keystore.jks -alias gateway -certreq -file conduktor.k8s.orb.local.csr -storepass conduktor -keypass conduktor

CERT_SERIAL=$(awk -v seed="$RANDOM" 'BEGIN { srand(seed); printf("0x%.4x%.4x%.4x%.4x\n", rand()*65535 + 1, rand()*65535 + 1, rand()*65535 + 1, rand()*65535 + 1) }')
openssl x509 -req -CA snakeoil-ca-1.crt -CAkey snakeoil-ca-1.key -in conduktor.k8s.orb.local.csr -out conduktor.k8s.orb.local-ca1-signed.crt -sha256 -days 365 -set_serial ${CERT_SERIAL} -passin pass:conduktor -extensions v3_req -extfile <(cat <<EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no
[req_distinguished_name]
CN = *.conduktor.k8s.orb.local
[v3_req]
extendedKeyUsage = serverAuth, clientAuth
EOF
)

keytool -noprompt -keystore conduktor.k8s.orb.local.keystore.jks -alias snakeoil-caroot -import -file snakeoil-ca-1.crt -storepass conduktor -keypass conduktor

keytool -noprompt -keystore conduktor.k8s.orb.local.keystore.jks -alias gateway -import -file conduktor.k8s.orb.local-ca1-signed.crt -storepass conduktor -keypass conduktor

popd