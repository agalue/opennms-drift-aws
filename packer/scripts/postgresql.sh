#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>
# Note: amazon-linux-extras supports Postgres (uses /var/lib/pgsql/data)

######### CUSTOMIZED VARIABLES #########

pg_version="11"

########################################

echo "### Installing PostgreSQL $pg_version..."

sudo yum install -y -q https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm
sudo sed -i -r 's/[$]releasever/7/g' /etc/yum.repos.d/pgdg-redhat-all.repo
sudo yum install -y -q postgresql$pg_version postgresql$pg_version-server postgresql$pg_version-contrib repmgr$pg_version
