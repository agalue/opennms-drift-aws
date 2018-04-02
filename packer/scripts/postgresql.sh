#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

######### CUSTOMIZED VARIABLES #########

pg_repo_version="9.6-3"

########################################

echo "### Installing PostgreSQL from repository version $pg_repo_version..."

pg_version=`echo $pg_repo_version | sed 's/-.//'`
pg_family=`echo $pg_version | sed 's/\.//'`

sudo yum install -y -q https://download.postgresql.org/pub/repos/yum/$pg_version/redhat/rhel-7-x86_64/pgdg-centos$pg_family-$pg_repo_version.noarch.rpm
sudo sed -i -r 's/[$]releasever/7/g' /etc/yum.repos.d/pgdg-$pg_family-centos.repo
sudo yum install -y -q postgresql$pg_family postgresql$pg_family-server postgresql$pg_family-contrib repmgr$pg_family
