#! /bin/bash

kcat -vvv -t test -C -b gateway.conduktor.k8s.orb.local:9092 \
    -X security.protocol=SASL_SSL -X sasl.mechanism=PLAIN \
    -X sasl.password=admin-secret -X sasl.username=admin \
    -X ssl.ca.location=$PWD/certs/rootCA.crt 1>/dev/null