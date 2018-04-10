#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

######### CUSTOMIZED VARIABLES #########

es_version="6.2.3"

########################################

echo "### Downloading and installing Kibana version $es_version..."

sudo yum install -y -q https://artifacts.elastic.co/downloads/kibana/kibana-${es_version}-x86_64.rpm

sudo -u kibana /usr/share/kibana/bin/kibana-plugin install x-pack
