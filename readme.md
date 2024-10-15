# Deploy Conduktor Gateway with Kubernetes and Host-based Routing

[!WARNING] Under construction. Coming soon.

## Introduction and Concepts

## Setup

I am running this tutorial on a Mac using Orbstack, which helps to run end-to-end authentically without incurring a cloud bill.

1. Install homebrew at [https://brew.sh/](https://brew.sh/).
1. Install `helm` and `orbstack` and a few other things.
    ```
    brew instal helm orbstack openssl openjdk
    ```
    [Helm](https://helm.sh/) is a package manager for Kubernetes.

    [Orbstack](https://orbstack.dev/) is a management system for containers and Linux VMs that makes it convenient to run Kubernetes locally, among other things.

    Openjdk is a Java runtime. This is required to use the `keytool` command to generate keystores and truststore for certificates. You may need to add it to your `PATH` in your shell profile for the shell to properly locate and execute the program. For example, add the following line to your `~/.zshrc` profile:
    ```bash
    export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"
    ```

## Prepare Certificates

This example will generate certificates that will be used by Kafka brokers and Gateway instances to establish secure connections using TLS.

This example will use TLS (formerly known as SSL) to encrypt data in transit between:
- between Kafka clients and Conduktor Gateway
- between Conduktor Gateway and Kafka

1. Run the following script to generate the keystores and truststore.

    ```bash
    ./generate-tls.sh
    ```

1. Inspect the certificates for various services. For example, inspect the gateway certificate.
    ```bash
    openssl x509 -in ./certs/gateway-ca1-signed.crt -text -noout
    ```
    [!IMPORTANT] Notice the Subject Alternate Names (SAN) that allow Gateway to present various hostnames to the client. This is crucial for hostname-based routing, also known as Server Name Indication (SNI) routing. Gateway can present a different hostname for each Kafka broker, which makes it possible to route Kafka client traffic through to the correct broker based solely on hostname rather than requiring a separate Gateway port per broker.


1. (Optional) Inspect the `generate-tls.sh` script to see how it
    - Creates a certificate authority (CA)
    - Creates a CA cert
    - Uses the CA cert to create service certificates for Kafka and Conduktor Gateway
    - Constructs Subject Alternate Names (SANs) to allow Gateway to present to clients as any broker.
    - Creates a truststore that clients can use to validate the identity of any service's certificate that has been signed by the CA



## Deploy

```bash
./start.sh
```


## Connect

### Java client

For some reason, Java clients need to run with this env var set:
```bash
export KAFKA_OPTS="-Djava.security.manager=allow"
```
You can also add ` -Djavax.net.debug=ssl` to enable ssl debug messages.

```bash
kafka-topics --list \
  --bootstrap-server franz-kafka.conduktor.svc.cluster.local:9092 \
  --command-config client.properties
```

```bash
kafka-topics --list \
  --bootstrap-server gateway.k8s.orb.local:9092 \
  --command-config client.properties
```

```
kafka-topics --bootstrap-server gateway.k8s.orb.local:9092 \
    --create --topic test --partitions 6 \
    --command-config client.properties
```

### Librdkafka

```bash
kcat -L -b franz-kafka.conduktor.svc.cluster.local:9092 \
    -X security.protocol=SASL_SSL -X sasl.mechanism=PLAIN \
    -X sasl.password=admin-secret -X sasl.username=admin \
    -X ssl.ca.location=./certs/snakeoil-ca-1.crt
```

```bash
kcat -L -b gateway.k8s.orb.local:9092 \
    -X security.protocol=SASL_SSL -X sasl.mechanism=PLAIN \
    -X sasl.password=admin-secret -X sasl.username=admin \
    -X ssl.ca.location=./certs/snakeoil-ca-1.crt
```

```bash
echo "hello1" | kcat -t test -P -b gateway.k8s.orb.local:9092 \
    -X security.protocol=SASL_SSL -X sasl.mechanism=PLAIN \
    -X sasl.password=admin-secret -X sasl.username=admin \
    -X ssl.ca.location=./certs/snakeoil-ca-1.crt
```

```bash
kcat -t test -C -b gateway.k8s.orb.local:9092 \
    -X security.protocol=SASL_SSL -X sasl.mechanism=PLAIN \
    -X sasl.password=admin-secret -X sasl.username=admin \
    -X ssl.ca.location=./certs/snakeoil-ca-1.crt
```
