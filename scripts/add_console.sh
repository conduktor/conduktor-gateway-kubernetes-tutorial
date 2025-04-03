#!/bin/bash


if ! kubectl get namespace conduktor >/dev/null 2>&1 ; then
    echo "execute start.sh before running this script"
    exit;    
fi

########################
# Create kubernetes secrets for Postgres

kubectl -n conduktor \
    create secret generic postgres-passwords \
        --from-literal=password=postgres \
        --from-literal=postgres-password=postgres

########################
# Create kubernetes secrets for Console

kubectl -n conduktor \
    create secret generic console-env-vars \
        --from-literal=CDK_ADMIN_EMAIL='admin@demo.dev' \
        --from-literal=CDK_ADMIN_PASSWORD='adminP4ss!' \
        --from-literal=CDK_DATABASE_PASSWORD='postgres' \
        --from-literal=CDK_DATABASE_USERNAME='postgres' \
        --from-literal=CDK_CLUSTERS_0_PROPERTIES='security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="admin" password="admin-secret";
ssl.truststore.location=/etc/gateway/tls/truststore/kafka.truststore.jks
ssl.truststore.password=conduktor' \
       --from-literal=CDK_CLUSTERS_1_PROPERTIES='security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="admin" password="admin-secret";
ssl.truststore.location=/etc/gateway/tls/truststore/kafka.truststore.jks
ssl.truststore.password=conduktor'

kubectl -n conduktor \
    create secret tls console-tls \
        --cert=$PWD/certs/console.conduktor.k8s.orb.local.crt \
        --key=$PWD/certs/console.conduktor.k8s.orb.local.unencrypted.key

########################
# Install components

# Install Postgres
helm install \
    -f $PWD/helm/postgres-values.yml \
    -n conduktor \
    postgresql oci://registry-1.docker.io/bitnamicharts/postgresql

# Install Conduktor Console
helm install \
    -f $PWD/helm/console-values.yml \
    -n conduktor \
    console conduktor/console

echo "Waiting for the Console to be available..."

# Wait for the admission webhook service to have endpoints
while true; do
    if kubectl -n conduktor get pods|grep 'console.*Running'|grep -v cortex|grep '1/1'; then
        echo "Console pod is ready! You can access it in the browser on https://console.conduktor.k8s.orb.local"
        echo "username: admin@demo.dev"
        echo "password: adminP4ss!"
        break
    fi
    echo "Waiting for Console pod to be ready..."
    sleep 5
done

echo "Installing ingress for Console"
kubectl apply -f $PWD/kubernetes/ingress-console.yml
