#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

######### CUSTOMIZED VARIABLES #########

repo_version="311x"

########################################

echo "### Downloading and installing Oracle JDK..."

sudo yum install -y -q http://yum.opennms.org/repofiles/opennms-repo-stable-rhel7.noarch.rpm
sudo rpm --import /etc/yum.repos.d/opennms-repo-stable-rhel7.gpg
sudo yum install -y -q jdk1.8.0_144
sudo yum erase -y -q opennms-repo-stable

echo "### Downloading and installing Cassandra..."

tmp_repo=/tmp/cassandra.repo 
cat <<EOF > $tmp_repo
[cassandra]
name=Apache Cassandra
baseurl=https://www.apache.org/dist/cassandra/redhat/${repo_version}/
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://www.apache.org/dist/cassandra/KEYS
EOF
sudo mv $tmp_repo /etc/yum.repos.d

sudo yum install -y -q cassandra cassandra-tools
