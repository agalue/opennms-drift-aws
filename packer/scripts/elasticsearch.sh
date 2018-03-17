#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>
# TODO: use EC2 discovery plugin.
# The Elasticsearch version cannot be changed due to required dependencies:
# https://github.com/OpenNMS/elasticsearch-drift-plugin

######### CUSTOMIZED VARIABLES #########

es_version="6.1.1"
maven_version="3.5.3"
plugin_branch="master"
plugin_name="elasticsearch-drift-plugin-1.0.0-SNAPSHOT"

########################################

echo "### Downloading and installing Elasticsearch..."

sudo yum install -y -q https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-${es_version}.rpm

sudo /usr/share/elasticsearch/bin/elasticsearch-plugin install --batch x-pack

echo "### Downloading and installing Curator..."

yum install -y -q https://packages.elastic.co/curator/5/centos/7/Packages/elasticsearch-curator-5.4.1-1.x86_64.rpm

echo "### Installing Maven..."

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

echo "### Installing the OpenNMS Drift Plugin from Source..."

mkdir ~/development
cd ~/development
sudo git clone https://github.com/OpenNMS/elasticsearch-drift-plugin.git
cd elasticsearch-drift-plugin
sudo git checkout -b $plugin_branch origin/$plugin_branch
sudo /opt/maven/bin/mvn install -q -DskipTests=true
sudo unzip target/releases/$plugin_name.zip -d elasticsearch
sudo zip /tmp/$plugin_name.zip elasticsearch/*
sudo /usr/share/elasticsearch/bin/elasticsearch-plugin install file:///tmp/$plugin_name.zip
cd