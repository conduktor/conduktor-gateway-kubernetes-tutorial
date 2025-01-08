#!/bin/bash

if [ ! -f ./certs/kafka.truststore.jks ]; then
    echo "create the keystore files before running this script"
    exit;    
fi



orb start k8s

# Create shared namespace
kubectl create namespace conduktor

########################
# Create kubernetes secrets for Kafka
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
########################
# Create kubernetes secrets for Gateway

# Use gateway.conduktor.k8s.orb.local.keystore.jks since that has the cert for Gateway.
# Use kafka.truststore.jks since that is the one that trusts the Kafka cert.
kubectl -n conduktor \
    create secret generic gateway-cert \
        --from-file=conduktor.k8s.orb.local.keystore.jks=./certs/conduktor.k8s.orb.local.keystore.jks \
        --from-file=kafka.truststore.jks=./certs/kafka.truststore.jks

kubectl -n conduktor \
    create secret generic gateway-env-vars \
        --from-literal=KAFKA_SASL_JAAS_CONFIG='org.apache.kafka.common.security.plain.PlainLoginModule required username="admin" password="admin-secret";' \
        --from-literal=GATEWAY_SSL_KEY_STORE_PASSWORD=conduktor \
        --from-literal=GATEWAY_SSL_KEY_PASSWORD=conduktor \
        --from-literal=GATEWAY_HTTPS_KEY_STORE_PASSWORD=conduktor \
        --from-literal=KAFKA_SSL_TRUSTSTORE_PASSWORD=conduktor

########################
# Install components

# Install Kafka via Bitnami's Kafka helm chart
helm install \
    -f ./helm/kafka-values.yml \
    -n conduktor \
    franz oci://registry-1.docker.io/bitnamicharts/kafka

# Add helm repos
helm repo add conduktor https://helm.conduktor.io
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install Gateway
helm install \
    -f ./helm/gateway-values.yml \
    -n conduktor \
    gateway conduktor/conduktor-gateway

# Install Ingress Controller
helm upgrade \
    --install ingress-nginx ingress-nginx/ingress-nginx \
    --set controller.extraArgs.enable-ssl-passthrough="true"

echo "Waiting for the ingress-nginx LoadBalancer IP to be available..."

# Wait for the admission webhook service to have endpoints
while true; do
    ENDPOINTS=$(kubectl get endpoints --namespace default ingress-nginx-controller-admission -o jsonpath='{.subsets[0].addresses}')
    if [[ -n "$ENDPOINTS" ]]; then
        echo "Admission webhook service is ready!"
        break
    fi
    echo "Waiting for admission webhook service to be ready..."
    sleep 1
done

# Create Ingress for Gateway
kubectl apply -f ingress.yml
