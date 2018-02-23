#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

######### CUSTOMIZED VARIABLES #########

es_version="6.1.1"

########################################

echo "### Downloading and installing Kibana..."

sudo yum install -y -q https://artifacts.elastic.co/downloads/kibana/kibana-${es_version}-x86_64.rpm

sudo -u kibana /usr/share/kibana/bin/kibana-plugin install x-pack
