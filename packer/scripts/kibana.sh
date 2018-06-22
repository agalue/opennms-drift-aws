#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

######### CUSTOMIZED VARIABLES #########

es_version="6.2.4"

########################################

kibana_config=/etc/kibana

echo "### Downloading and installing Kibana version $es_version..."

sudo yum install -y -q https://artifacts.elastic.co/downloads/kibana/kibana-$es_version-x86_64.rpm
sudo -u kibana /usr/share/kibana/bin/kibana-plugin install x-pack

echo "### Initializing GIT at $kibana_config..."

sudo cd $kibana_config
sudo git config --global user.name "OpenNMS"
sudo git config --global user.email "support@opennms.org"
sudo git init .
sudo git add .
sudo git commit -m "Kibana $es_version installed."
cd
