#!/bin/sh

docker run --rm -p 9000:9000 -e ZK_HOSTS=zookeeper1:2181,zookeeper2:2181,zookeeper3:2181 sheepkiller/kafka-manager:alpine
