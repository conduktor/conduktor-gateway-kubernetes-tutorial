#! /bin/bash

export KAFKA_OPTS="-Djava.security.manager=allow"

kafka-topics --create --topic test \
    --if-not-exists \
    --bootstrap-server gateway.conduktor.k8s.orb.local:9092 \
    --command-config $PWD/client.properties

kafka-producer-perf-test \
    --topic test \
    --throughput 10 \
    --record-size 100 \
    --num-records 10000000 \
    --producer-props bootstrap.servers=gateway.conduktor.k8s.orb.local:9092 \
    --producer.config $PWD/client.properties