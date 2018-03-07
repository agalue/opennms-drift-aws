#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>
# TODO: use EC2 discovery plugin.
# The Elasticsearch version cannot be changed due to required dependencies:
# https://github.com/OpenNMS/elasticsearch-drift-plugin

######### CUSTOMIZED VARIABLES #########

es_version="6.1.1"

########################################

echo "### Downloading and installing Elasticsearch..."

sudo yum install -y -q https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-${es_version}.rpm

sudo /usr/share/elasticsearch/bin/elasticsearch-plugin install --batch x-pack
