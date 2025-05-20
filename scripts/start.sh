#!/bin/bash

if [ ! -f ./certs/kafka.truststore.jks ]; then
    $PWD/scripts/generate-tls.sh
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
        --from-file=kafka.truststore.jks=$PWD/certs/kafka.truststore.jks \
        --from-file=kafka.keystore.jks=$PWD/certs/kafka.keystore.jks
########################
# Create kubernetes secrets for Gateway

# Use gateway.k8s.tutorial.keystore.jks since that has the cert for Gateway.
# Use kafka.truststore.jks since that is the one that trusts the Kafka cert.
kubectl -n conduktor \
    create secret generic gateway-cert \
        --from-file=gateway.k8s.tutorial.keystore.jks=$PWD/certs/gateway.k8s.tutorial.keystore.jks \
        --from-file=kafka.truststore.jks=$PWD/certs/kafka.truststore.jks

kubectl -n conduktor \
    create secret generic gateway-env-vars \
        --from-literal=KAFKA_SASL_JAAS_CONFIG='org.apache.kafka.common.security.plain.PlainLoginModule required username="admin" password="admin-secret";' \
        --from-literal=GATEWAY_SSL_KEY_STORE_PASSWORD=conduktor \
        --from-literal=GATEWAY_SSL_KEY_PASSWORD=conduktor \
        --from-literal=GATEWAY_HTTPS_KEY_STORE_PASSWORD=conduktor \
        --from-literal=KAFKA_SSL_TRUSTSTORE_PASSWORD=conduktor \
        --from-literal=GATEWAY_ADMIN_API_USERS='[{username: admin, password: conduktor, admin: true}]'

########################
# Install components

# Install Kafka via Bitnami's Kafka helm chart
helm upgrade --install \
    -f $PWD/helm/kafka-values.yml \
    -n conduktor \
    --version 31.1.0 \
    franz oci://registry-1.docker.io/bitnamicharts/kafka

# Add helm repos
helm repo add conduktor https://helm.conduktor.io
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install Gateway
helm upgrade --install \
    -f $PWD/helm/gateway-values.yml \
    -n conduktor \
    gateway conduktor/conduktor-gateway


# Install Ingress Controller
kubectl create namespace ingress-nginx
# kubectl apply -f $PWD/kubernetes/ingress-tcp-configmap.yml

helm upgrade \
    --install ingress-nginx ingress-nginx/ingress-nginx \
    --namespace ingress-nginx \
    -f $PWD/helm/ingress-nginx-values.yml

# kubectl patch svc ingress-nginx-controller -n ingress-nginx \
#   --type='json' \
#   -p='[{"op":"add","path":"/spec/ports/-","value":{"name":"tcp-9092","port":9092,"protocol":"TCP","targetPort":9092}}]'


echo "Waiting for the ingress-nginx LoadBalancer IP to be available..."

# Wait for the admission webhook service to have endpoints
while true; do
    ENDPOINTS=$(kubectl get endpoints --namespace ingress-nginx ingress-nginx-controller-admission -o jsonpath='{.subsets[0].addresses}')
    if [[ -n "$ENDPOINTS" ]]; then
        echo "Admission webhook service is ready!"
        break
    fi
    echo "Waiting for admission webhook service to be ready..."
    sleep 1
done

# Create Ingress for Gateway
kubectl apply -f $PWD/kubernetes/ingress.yml
