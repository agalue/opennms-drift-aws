#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>
# Warning: The version family should match the Packer image
# TODO: Configure master/slave streaming replication based on pg_role

# AWS Template Variables

vpc_cidr="${vpc_cidr}"
hostname="${hostname}"
domainname="${domainname}"
pg_max_connections="${pg_max_connections}"
pg_version_family="${pg_version_family}"
pg_role="${pg_role}"

echo "### Configuring Hostname and Domain..."

sed -i -r "s/HOSTNAME=.*/HOSTNAME=$hostname.$domainname/" /etc/sysconfig/network
hostname $hostname.$domainname
domainname $domainname
sed -i -r "s/#Domain =.*/Domain = $domainname/" /etc/idmapd.conf

echo "### Configuring PostgreSQL..."

pg_version=`echo $pg_version_family | sed 's/-.//'`
pg_family=`echo $pg_version | sed 's/\.//'`

/usr/pgsql-$pg_version/bin/postgresql$pg_family-setup initdb

data_dir=/var/lib/pgsql/$pg_version/data
sed -r -i 's/(peer|ident)/trust/g' $data_dir/pg_hba.conf
sed -r -i 's|127.0.0.1/32|${vpc_cidr}|g' $data_dir/pg_hba.conf
sed -r -i "s/[#]?listen_addresses =.*/listen_addresses = '*'/" $data_dir/postgresql.conf
sed -r -i "s/[#]?max_connections =.*/max_connections = $pg_max_connections/" $data_dir/postgresql.conf

echo "### Enabling and starting PostgreSQL..."

systemctl enable postgresql-$pg_version
systemctl start postgresql-$pg_version

echo "### Enabling and starting SNMP..."

systemctl enable snmpd
systemctl start snmpd
