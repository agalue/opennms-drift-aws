#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>
#
# Set the USE_LATEST_JAVA environment variable in order to use latest Java instead of Java 8

echo "### Downloading and installing latest OpenJDK..."

java_rpms="java-1.8.0-openjdk-devel java-1.8.0-openjdk-headless"
if [ "$USE_LATEST_JAVA" != "" ]; then
  java_rpms="java-11-openjdk-devel java-11-openjdk-headless"
fi

sudo yum install -y -q $java_rpms
