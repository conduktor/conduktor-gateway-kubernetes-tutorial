#! /bin/bash

export KAFKA_OPTS="-Djava.security.manager=allow"

kafka-consumer-perf-test \
    --topic test \
    --bootstrap-server gateway.k8s.tutorial:9092 \
    --consumer.config $PWD/client.properties \
    --messages 10000000 \
    --timeout 120000 \
    --show-detailed-stats