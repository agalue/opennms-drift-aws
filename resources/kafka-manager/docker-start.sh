#!/bin/sh

docker run --rm -p 9000:9000 -e ZK_HOSTS=zookeeper1.aws.opennms.org:2181 hlebalbau/kafka-manager:latest
