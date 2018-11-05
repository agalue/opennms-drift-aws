#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

######### CUSTOMIZED VARIABLES #########

maven_version="3.6.0"

########################################

echo "### Installing Dependencies..."

sudo yum install -y -q rpm-build

echo "### Installing Maven version $maven_version..."

maven_name=apache-maven-$maven_version
maven_file=$maven_name-bin.zip
maven_mirror=$(curl --stderr /dev/null https://www.apache.org/dyn/closer.cgi\?as_json\=1 | jq -r '.preferred')
maven_url="${maven_mirror}maven/maven-3/$maven_version/binaries/$maven_file"

cd /opt
sudo wget -q "$maven_url" -O "$maven_file"
sudo unzip -q $maven_file
sudo chown -R root:root $maven_name
sudo ln -s $maven_name maven
sudo rm -f $maven_file
cd

echo "### Compiling OpenNMS Correlation Engine (OCE)..."

export PATH=/opt/maven/bin:$PATH
git clone https://github.com/OpenNMS/oce.git
cd oce
mvn -q -DskipTests package install
cd
