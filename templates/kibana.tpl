#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>
# Warning: This is intended to be used through Terraform's template plugin only

# AWS Template Variables
# - vpc_cidr
# - hostname
# - domainname
# - es_version
# - es_url

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

echo "### Installing Elasticsearch and Kibana..."

yum install -y -q https://artifacts.elastic.co/downloads/kibana/kibana-${es_version}-x86_64.rpm

echo "### Configuring Kibana..."

kb_dir=/etc/kibana
kb_yaml=$kb_dir/kibana.yml

sed -i -r "s/[#]server.host:.*/server.host: ${hostname}/" $kb_yaml
sed -i -r "s/[#]server.name:.*/server.name: ${hostname}/"  $kb_yaml
sed -i -r "s|[#]elasticsearch.url:.*|elasticsearch.url: ${es_url}|" $kb_yaml

echo "### Enabling and starting Kibana..."

chkconfig kibana on
service kibana start
