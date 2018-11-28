#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>
# The Elasticsearch version cannot be changed due to required dependencies:
# https://github.com/OpenNMS/elasticsearch-drift-plugin
# The plugin RPM depends on 6.2.4

######### CUSTOMIZED VARIABLES #########

es_version="6.2.4"
curator_version="5.4.1"

########################################

es_config=/etc/elasticsearch

echo "### Downloading and installing Elasticsearch version $es_version..."

sudo yum install -y -q https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-$es_version.rpm
sudo /usr/share/elasticsearch/bin/elasticsearch-plugin install --batch x-pack

echo "### Initializing GIT at $es_config..."

sudo cd $es_config
sudo git init .
sudo git add .
sudo git commit -m "Elasticsearch $es_version installed."
cd

echo "### Downloading and installing Curator version $curator_version..."

sudo yum install -y -q https://packages.elastic.co/curator/5/centos/7/Packages/elasticsearch-curator-$curator_version-1.x86_64.rpm

echo "### Installing the OpenNMS Drift Plugin..."

sudo yum install -y -q http://yum.opennms.org/repofiles/opennms-repo-stable-rhel7.noarch.rpm
sudo rpm --import /etc/yum.repos.d/opennms-repo-stable-rhel7.gpg
sudo yum install -y -q elasticsearch-drift-plugin
