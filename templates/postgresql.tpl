#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

# AWS Template Variables
# - vpc_cidr
# - hostname
# - domainname
# - pg_repo_version

echo "### Configuring Hostname and Domain..."

sed -i -r "s/HOSTNAME=.*/HOSTNAME=${hostname}.${domainname}/" /etc/sysconfig/network
hostname ${hostname}.${domainname}
domainname ${domainname}

echo "### Configuring Timezone..."

timezone=America/New_York
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
sed -i -r "s|ZONE=.*|ZONE=$timezone|" /etc/sysconfig/clock

echo "### Installing common packages..."

yum -y -q update
yum -y -q install jq net-snmp net-snmp-utils git pytz dstat htop sysstat

echo "### Configuring and enabling SNMP..."

snmp_cfg=/etc/snmp/snmpd.conf
cp $snmp_cfg $snmp_cfg.original
cat <<EOF > $snmp_cfg
com2sec localUser ${vpc_cidr} public
group localGroup v1 localUser
group localGroup v2c localUser
view all included .1 80
access localGroup "" any noauth 0 all none none
syslocation AWS
syscontact Account Manager
dontLogTCPWrappersConnects yes
disk /
EOF

chmod 600 $snmp_cfg
chkconfig snmpd on
service snmpd start snmpd

echo "### Installing PostgreSQL..."

pg_version=`echo ${pg_repo_version} | sed 's/-.//'`
pg_family=`echo $pg_version | sed 's/\.//'`

yum install -y -q https://download.postgresql.org/pub/repos/yum/$pg_version/redhat/rhel-6-x86_64/pgdg-ami201503-$pg_family-${pg_repo_version}.noarch.rpm
yum install -y -q postgresql$pg_family postgresql$pg_family-server

echo "### Configuring PostgreSQL..."

service postgresql96 initdb
data_dir=/var/lib/pgsql$pg_family/data
sed -r -i 's/(peer|ident)/trust/g' $data_dir/pg_hba.conf
sed -r -i 's|127.0.0.1/32|${vpc_cidr}|g' $data_dir/pg_hba.conf
sed -r -i "s/[#]listen_addresses =.*/listen_addresses = '*'/" $data_dir/postgresql.conf

echo "### Enabling and starting PostgreSQL..."

chkconfig postgresql96 on
service postgresql96 start
