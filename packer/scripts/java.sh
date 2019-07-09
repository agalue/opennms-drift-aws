#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>
#
# Set the USE_LATEST_JAVA environment variable in order to use latest Java instead of Java 8

echo "### Downloading and installing latest OpenJDK..."

if [ "$USE_LATEST_JAVA" != "" ]; then
  sudo amazon-linux-extras install java-openjdk11 -y
  sudo yum install -y -q java-11-openjdk-devel
else
  sudo yum install -y -q java-1.8.0-openjdk-devel java-1.8.0-openjdk-headless
fi

