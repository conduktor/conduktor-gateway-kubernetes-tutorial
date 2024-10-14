#!/bin/bash

kubectl create namespace conduktor

kubectl -n conduktor \
    create secret generic keystore-passwords \
        --from-literal=keystore-password=conduktor \
        --from-literal=truststore-password=conduktor

kubectl -n conduktor \
    create secret generic client-passwords \
        --from-literal=client-passwords=admin-secret \
        --from-literal=inter-broker-password=admin-secret \
        --from-literal=controller-password=admin-secret 

kubectl -n conduktor \
    create secret generic kafka-cert \
        --from-file=kafka.truststore.jks=./certs/kafka.truststore.jks \
        --from-file=kafka.keystore.jks=./certs/kafka.keystore.jks

# Use gateway.keystore.jks since that has the cert for Gateway.
# Use kafka.truststore.jks since that is the one that trusts the Kafka cert.
kubectl -n conduktor \
    create secret generic gateway-cert \
        --from-file=gateway.keystore.jks=./certs/gateway.keystore.jks \
        --from-file=kafka.truststore.jks=./certs/kafka.truststore.jks

kubectl -n conduktor \
    create secret generic gateway-env-vars \
        --from-literal=KAFKA_SASL_JAAS_CONFIG='org.apache.kafka.common.security.plain.PlainLoginModule required username="admin" password="admin-secret";' \
        --from-literal=GATEWAY_SSL_KEY_STORE_PASSWORD=conduktor \
        --from-literal=GATEWAY_SSL_KEY_PASSWORD=conduktor \
        --from-literal=KAFKA_SSL_TRUSTSTORE_PASSWORD=conduktor


helm install \
    -f ./helm/kafka-values.yml \
    -n conduktor \
    franz oci://registry-1.docker.io/bitnamicharts/kafka

helm repo add conduktor https://helm.conduktor.io
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install \
    -f ./helm/gateway-values.yml \
    -n conduktor \
    gateway conduktor/conduktor-gateway

helm upgrade \
    --install ingress-nginx ingress-nginx/ingress-nginx \
    --set controller.extraArgs.enable-ssl-passthrough="true"

kubectl apply -f ingress.yml
