#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>
# Warning: This is intended to be used through Terraform's template plugin only
# Warning: The repo version should match the Packer image

# AWS Template Variables
# - vpc_cidr = ${vpc_cidr}
# - hostname = ${hostname}
# - domainname = ${domainname}
# - pg_num_connections = ${pg_num_connections}

echo "### Configuring Hostname and Domain..."

sed -i -r "s/HOSTNAME=.*/HOSTNAME=${hostname}.${domainname}/" /etc/sysconfig/network
hostname ${hostname}.${domainname}
domainname ${domainname}

echo "### Configuring Timezone..."

timezone=America/New_York
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime

echo "### Configuring PostgreSQL..."

pg_repo_version="9.6-3"
pg_version=`echo $pg_repo_version | sed 's/-.//'`
pg_family=`echo $pg_version | sed 's/\.//'`

/usr/pgsql-$pg_version/bin/postgresql$pg_family-setup initdb

data_dir=/var/lib/pgsql/$pg_version/data
sed -r -i 's/(peer|ident)/trust/g' $data_dir/pg_hba.conf
sed -r -i 's|127.0.0.1/32|${vpc_cidr}|g' $data_dir/pg_hba.conf
sed -r -i "s/[#]?listen_addresses =.*/listen_addresses = '*'/" $data_dir/postgresql.conf
sed -r -i "s/[#]?max_connections =.*/max_connections = ${pg_num_connections}/" $data_dir/postgresql.conf

echo "### Enabling and starting PostgreSQL..."

systemctl enable postgresql-$pg_version
systemctl start postgresql-$pg_version

systemctl enable snmpd
systemctl start snmpd
