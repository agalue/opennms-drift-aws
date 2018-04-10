#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

# AWS Template Variables

hostname="${hostname}"
domainname="${domainname}"
es_url="${es_url}"
es_password="${es_password}"
es_monsrv="${es_monsrv}"

echo "### Configuring Hostname and Domain..."

ip_address=`curl http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null`
hostnamectl set-hostname --static $hostname
echo "preserve_hostname: true" > /etc/cloud/cloud.cfg.d/99_hostname.cfg
sed -i -r "s/^[#]?Domain =.*/Domain = $domainname/" /etc/idmapd.conf

echo "### Configuring Kibana..."

kb_dir=/etc/kibana
kb_yaml=$kb_dir/kibana.yml
cp $kb_yaml $kb_yaml.bak

sed -i -r "s/[#]server.host:.*/server.host: $hostname/" $kb_yaml
sed -i -r "s/[#]server.name:.*/server.name: $hostname/"  $kb_yaml
sed -i -r "s|[#]elasticsearch.url:.*|elasticsearch.url: $es_url|" $kb_yaml
sed -i -r "s/[#]elasticsearch.username:.*/elasticsearch.username: kibana/" $kb_yaml
sed -i -r "s/[#]elasticsearch.password:.*/elasticsearch.password: $es_password/" $kb_yaml

if [[ "$es_monsrv" != "" ]]; then
  echo >> $kb_yaml
  echo xpack.monitoring.elasticsearch.url: "http://$es_monsrv:9200" >> $kb_yaml
fi

echo "### Enabling and starting Kibana..."

until $$(curl --output /dev/null --silent --head --fail -u "elastic:$es_password" $es_url); do
  printf '.'
  sleep 5
done

systemctl enable kibana
systemctl start kibana

echo "### Enabling and starting SNMP..."

systemctl enable snmpd
systemctl start snmpd
