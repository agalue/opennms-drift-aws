#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

######### CUSTOMIZED VARIABLES #########

amq_version="5.13.5"

########################################

echo "### Downloading and installing ActiveMQ..."

amq_name=apache-activemq-$amq_version
amq_file=$amq_name-bin.tar.gz
amq_mirror=$(curl --stderr /dev/null https://www.apache.org/dyn/closer.cgi\?as_json\=1 | jq -r '.preferred')
amq_url="${amq_mirror}activemq/$amq_version/$amq_file"

cd /opt

sudo wget -q "$amq_url" -O "$amq_file"
sudo tar xzf $amq_file
sudo chown -R root:root $amq_file
sudo ln -s $amq_name activemq
sudo rm -f $amq_file
