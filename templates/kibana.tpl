#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>
# Warning: This is intended to be used through Terraform's template plugin only

# AWS Template Variables
# - vpc_cidr = ${vpc_cidr}
# - hostname = ${hostname}
# - domainname = ${domainname}
# - es_version = ${es_version}
# - es_url = ${es_url}
# - es_password = ${es_password}
# - es_monsrv = ${es_monsrv}

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
yum -y -q install jq net-snmp net-snmp-utils git pytz dstat htop sysstat nmap-ncat

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
systemctl enable snmpd
systemctl start snmpd

echo "### Downloading and installing Kibana..."

yum install -y -q https://artifacts.elastic.co/downloads/kibana/kibana-${es_version}-x86_64.rpm
sudo -u kibana /usr/share/kibana/bin/kibana-plugin install x-pack

echo "### Configuring Kibana..."

kb_dir=/etc/kibana
kb_yaml=$kb_dir/kibana.yml
cp $kb_yaml $kb_yaml.bak

sed -i -r "s/[#]server.host:.*/server.host: ${hostname}/" $kb_yaml
sed -i -r "s/[#]server.name:.*/server.name: ${hostname}/"  $kb_yaml
sed -i -r "s|[#]elasticsearch.url:.*|elasticsearch.url: ${es_url}|" $kb_yaml
sed -i -r "s/[#]elasticsearch.username:.*/elasticsearch.username: kibana/" $kb_yaml
sed -i -r "s/[#]elasticsearch.password:.*/elasticsearch.password: ${es_password}/" $kb_yaml

if [[ "${es_monsrv}" != "" ]]; then
  echo >> $kb_yaml
  echo xpack.monitoring.elasticsearch.url: "http://${es_monsrv}:9200" >> $kb_yaml
fi

echo "### Enabling and starting Kibana..."

until $$(curl --output /dev/null --silent --head --fail -u "elastic:${es_password}" ${es_url}); do
  printf '.'
  sleep 5
done

systemctl enable kibana
systemctl start kibana
