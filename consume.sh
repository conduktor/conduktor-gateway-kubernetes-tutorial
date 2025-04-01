#! /bin/bash

export KAFKA_OPTS="-Djava.security.manager=allow"

kafka-consumer-perf-test \
    --topic test \
    --bootstrap-server gateway.conduktor.k8s.orb.local:9092 \
    --consumer.config client.properties \
    --messages 10000000 \
    --timeout 120000 \
    --show-detailed-stats