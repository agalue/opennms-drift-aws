#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

######### CUSTOMIZED VARIABLES #########

sentinel_repo="branches-features-sentinel"
sentinel_version="-latest-"

########################################

sentinel_home=/opt/sentinel
sentinel_etc=$sentinel_home/etc
tmp_file=/tmp/_onms_temp_file

echo "### Installing Common Packages..."

sudo yum -y -q install haveged redis httpd
sudo systemctl enable haveged

echo "### Installing OpenNMS..."

echo "### Installing OpenNMSS $sentinel_repo Repository..."
sudo yum install -y -q http://yum.opennms.org/repofiles/opennms-repo-$sentinel_repo-rhel7.noarch.rpm
sudo rpm --import /etc/yum.repos.d/opennms-repo-$sentinel_repo-rhel7.gpg
sudo yum install -y -q opennms-sentinel*

echo "### Initializing GIT at $sentinel_etc..."

cd $sentinel_etc
sudo git config --global user.name "OpenNMS"
sudo git config --global user.email "support@opennms.org"
sudo git init .
sudo git add .
sudo git commit -m "Sentinel Installed."
cd
