#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>
# Note: amazon-linux-extras supports PG 9.6 (uses /var/lib/pgsql/data)

######### CUSTOMIZED VARIABLES #########

pg_repo_version="10-2"
pg_repo_os="centos"

########################################

echo "### Installing PostgreSQL from repository version $pg_repo_version..."

pg_version=`echo $pg_repo_version | sed 's/-.//'`
pg_family=`echo $pg_version | sed 's/\.//'`

sudo yum install -y -q https://download.postgresql.org/pub/repos/yum/$pg_version/redhat/rhel-7-x86_64/pgdg-$pg_repo_os$pg_family-$pg_repo_version.noarch.rpm
sudo sed -i -r 's/[$]releasever/7/g' /etc/yum.repos.d/pgdg-$pg_family-$pg_repo_os.repo
sudo yum install -y -q postgresql$pg_family postgresql$pg_family-server postgresql$pg_family-contrib repmgr$pg_family
