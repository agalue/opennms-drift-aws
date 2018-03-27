#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

# AWS Template Variables

node_id="${node_id}"
hostname="${hostname}"
domainname="${domainname}"
es_cluster_name="${es_cluster_name}"
es_seed_name="${es_seed_name}"
es_password="${es_password}"
es_role="${es_role}"
es_xpack="${es_xpack}"
es_monsrv="${es_monsrv}"

echo "### Configuring Hostname and Domain..."

sed -i -r "s/HOSTNAME=.*/HOSTNAME=$hostname.$domainname/" /etc/sysconfig/network
hostname $hostname.$domainname
domainname $domainname
sed -i -r "s/#Domain =.*/Domain = $domainname/" /etc/idmapd.conf

echo "### Configuring Elasticsearch..."

es_dir=/etc/elasticsearch
es_yaml=$es_dir/elasticsearch.yml
es_jvm=$es_dir/jvm.options
cp $es_yaml $es_yaml.bak
cp $es_jvm $es_jvm.bak

total_mem_in_mb=`free -m | awk '/:/ {print $2;exit}'`
mem_in_mb=`expr $total_mem_in_mb / 2`
if [ "$mem_in_mb" -gt "30720" ]; then
  mem_in_mb="30720"
fi
sed -i -r "s/^-Xms1g/-Xms$${mem_in_mb}m/" $es_jvm
sed -i -r "s/^-Xmx1g/-Xmx$${mem_in_mb}m/" $es_jvm

sed -i -r "s/[#]?cluster.name:.*/cluster.name: $es_cluster_name/" $es_yaml
sed -i -r "s/[#]?network.host:.*/network.host: $hostname/" $es_yaml
sed -i -r "s/[#]?node.name:.*/node.name: $hostname/" $es_yaml

if [[ "$es_seed_name" != "" ]]; then
  sed -i -r "s/[#]?discovery.zen.minimum_master_nodes:.*/discovery.zen.minimum_master_nodes: 2/" $es_yaml
  sed -i -r "s/[#]?discovery.zen.ping.unicast.hosts:.*/discovery.zen.ping.unicast.hosts: [$es_seed_name]/" $es_yaml
fi

echo >> $es_yaml

if [[ "$es_role" == "master" ]]; then
  echo "node.master: true" >> $es_yaml
  echo "node.data: false" >> $es_yaml
  echo "node.ingest: false" >> $es_yaml
fi

if [[ "$es_role" == "data" ]]; then
  echo "node.master: false" >> $es_yaml
  echo "node.data: true" >> $es_yaml
  echo "node.ingest: true" >> $es_yaml
fi

if [[ "$es_role" == "coordinator" ]]; then
  echo "node.master: false" >> $es_yaml
  echo "node.data: false" >> $es_yaml
  echo "node.ingest: false" >> $es_yaml
fi

echo >> $es_yaml
echo "xpack.license.self_generated.type: basic" >> $es_yaml

if [[ "$es_xpack" == "true" ]]; then
  echo $es_password | /usr/share/elasticsearch/bin/elasticsearch-keystore add -x 'bootstrap.password'

  if [[ "$es_monsrv" != "" ]]; then
    echo "xpack.monitoring.exporters:" >> $es_yaml
    echo "  remote: " >> $es_yaml
    echo "    type: http" >> $es_yaml
    echo "    host: [ $es_monsrv ]" >> $es_yaml
    echo "    connection:" >> $es_yaml
    echo "      timeout: 6s" >> $es_yaml
    echo "      read_timeout: 60s" >> $es_yaml
  fi
else
  echo "xpack.security.enabled=false" >> $es_yaml
  echo "xpack.monitoring.enabled=false" >> $es_yaml
fi

echo "### Checking cluster prior start..."

start_delay=$((30*($node_id-1)))
if [[ $start_delay != 0 ]]; then
  echo "### Waiting $start_delay seconds prior starting Elasticsearch..."
  sleep $start_delay
fi

echo "### Enabling and starting Elasticsearch..."

systemctl enable elasticsearch
systemctl start elasticsearch

echo "### Enabling and starting SNMP..."

systemctl enable snmpd
systemctl start snmpd
