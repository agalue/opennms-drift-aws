#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

######### CUSTOMIZED VARIABLES #########

repo_version="311x"

########################################

cassandra_config=/etc/cassandra/conf

echo "### Downloading and installing Cassandra $repo_version..."

cat <<EOF | sudo tee -a /etc/yum.repos.d/cassandra.repo
[cassandra]
name=Apache Cassandra
baseurl=https://www.apache.org/dist/cassandra/redhat/$repo_version/
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://www.apache.org/dist/cassandra/KEYS
EOF

sudo yum install -y -q cassandra cassandra-tools

echo "### Initializing GIT at $cassandra_config..."

cd $cassandra_config
sudo git init .
sudo git add .
sudo git commit -m "Cassandra $repo_version installed."
cd
