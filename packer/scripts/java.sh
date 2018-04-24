#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

echo "### Downloading and installing latest Oracle JDK 8..."

java_url="http://download.oracle.com/otn-pub/java/jdk/8u172-b11/a58eab1ec242421181065cdc37240b08/jdk-8u172-linux-x64.rpm"
java_rpm=/tmp/jdk8-linux-x64.rpm

wget -c --quiet --header "Cookie: oraclelicense=accept-securebackup-cookie" -O $java_rpm $java_url

if [ ! -s $java_rpm ]; then
  echo "FATAL: Cannot download Java from $java_url. Using OpenNMS default ..."
  sudo yum install -y -q http://yum.opennms.org/repofiles/opennms-repo-stable-rhel7.noarch.rpm
  sudo rpm --import /etc/yum.repos.d/opennms-repo-stable-rhel7.gpg
  sudo yum install -y -q jdk1.8.0_144
  sudo yum erase -y -q opennms-repo-stable
else
  sudo yum install -y -q $java_rpm
  sudo rm -f $java_rpm
fi
