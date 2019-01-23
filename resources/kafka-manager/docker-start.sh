#!/bin/sh

docker run -it --rm --name kafka-manager \
 -p 9000:9000 \
 -e ZK_HOSTS=zookeeper1.aws.opennms.org:2181 \
 -v "$(pwd)/consumer.properties":/kafka-manager/conf/consumer.properties \
 hlebalbau/kafka-manager:latest
