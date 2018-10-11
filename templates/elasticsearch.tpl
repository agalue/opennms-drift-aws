#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>

# AWS Template Variables

node_id="${node_id}"
hostname="${hostname}"
domainname="${domainname}"
dependencies="${dependencies}"
es_cluster_name="${es_cluster_name}"
es_seed_name="${es_seed_name}"
es_password="${es_password}"
es_license="${es_license}"
es_role="${es_role}"
es_xpack="${es_xpack}"
es_monsrv="${es_monsrv}"

echo "### Configuring Hostname and Domain..."

ip_address=`curl http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null`
hostnamectl set-hostname --static $hostname
echo "preserve_hostname: true" > /etc/cloud/cloud.cfg.d/99_hostname.cfg
sed -i -r "s/^[#]?Domain =.*/Domain = $domainname/" /etc/idmapd.conf

echo "### Configuring Elasticsearch..."

es_dir=/etc/elasticsearch
es_yaml=$es_dir/elasticsearch.yml
es_jvm=$es_dir/jvm.options

# JVM Memory

total_mem_in_mb=`free -m | awk '/:/ {print $2;exit}'`
mem_in_mb=`expr $total_mem_in_mb / 2`
if [ "$mem_in_mb" -gt "30720" ]; then
  mem_in_mb="30720"
fi
sed -i -r "s/^-Xms1g/-Xms$${mem_in_mb}m/" $es_jvm
sed -i -r "s/^-Xmx1g/-Xmx$${mem_in_mb}m/" $es_jvm

# Basic Configuration

sed -i -r "s/[#]?cluster.name:.*/cluster.name: $es_cluster_name/" $es_yaml
sed -i -r "s/[#]?network.host:.*/network.host: $ip_address/" $es_yaml
sed -i -r "s/[#]?node.name:.*/node.name: $hostname/" $es_yaml

if [ "$es_seed_name" != "" ]; then
  sed -i -r "s/[#]?discovery.zen.minimum_master_nodes:.*/discovery.zen.minimum_master_nodes: 2/" $es_yaml
  sed -i -r "s/[#]?discovery.zen.ping.unicast.hosts:.*/discovery.zen.ping.unicast.hosts: [$es_seed_name]/" $es_yaml
fi

# Roles

echo >> $es_yaml

if [ "$es_role" == "master" ]; then
  echo "node.master: true" >> $es_yaml
  echo "node.data: false" >> $es_yaml
  echo "node.ingest: false" >> $es_yaml
fi

if [ "$es_role" == "data" ]; then
  echo "node.master: false" >> $es_yaml
  echo "node.data: true" >> $es_yaml
  echo "node.ingest: true" >> $es_yaml
fi

if [ "$es_role" == "coordinator" ]; then
  echo "node.master: false" >> $es_yaml
  echo "node.data: false" >> $es_yaml
  echo "node.ingest: false" >> $es_yaml
fi

# X-Pack

cat <<EOF >> $es_yaml

xpack.license.self_generated.type: $es_license
EOF

if [ "$es_xpack" == "true" ]; then
  echo $es_password | /usr/share/elasticsearch/bin/elasticsearch-keystore add --stdin 'bootstrap.password'

  if [ "$es_monsrv" != "" ]; then
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

# CORS (Required to use Grafana Plugin)

cat <<EOF >> $es_yaml

http.cors.enabled: true
http.cors.allow-origin: "*"
EOF

# Curator

if [ "$es_role" == "master" ]; then
  echo "### Configuring Curator..."

  cat <<EOF > /etc/elasticsearch-curator/config.yml
client:
  host:
    - $es_seed_name
  port: 9200
  url_prefix:
  use_ssl: false
  certificate:
  client_cert:
  client_key:
  ssl_no_validate: False
  http_auth:
  timeout: 30
  master_only: True

logging:
  loglevel: INFO
  logfile:
  logformat: default
  blacklist: ['elasticsearch', 'urllib3']
EOF

  cat <<EOF > /etc/elasticsearch-curator/delete_indices.yml
actions:
  1:
    action: delete_indices
    description: >-
      Delete indices older than 30 days.
    options:
      ignore_empty_list: True
      disable_action: False
    filters:
      - filtertype: pattern
        kind: prefix
        value: netflow-
      - filtertype: age
        source: name
        direction: older
        timesharing: '%Y-%m-%d-%H'
        unit: hours
        unit_count: 720
EOF

cat <<EOF > /etc/elasticsearch-curator/forcemerge_indices.yml
actions:
  1:
    action: forcemerge
    description: >-
      Force merge Netflow indices
    options:
      num_max_segments: 1
      delay: 120
      timneout_override:
      continue_if_exeption: False
      disable_action: False
    filters:
      - filtertype: pattern
        kind: prefix
        value: netflow-
      - filtertype: age
        source: name
        direction: older
        timesharing: '%Y-%m-%d-%H'
        unit: hours
        unit_count: 12
      - filtertype: forcemerged
        max_num_segments: 1
EOF
fi

echo "### Checking cluster prior start..."

if [ "$dependencies" != "" ]; then
  for service in $${dependencies//,/ }; do
    data=($${service//:/ })
    echo "Waiting for server $${data[0]} on port $${data[1]}..."
    until printf "" 2>>/dev/null >>/dev/tcp/$${data[0]}/$${data[1]}; do printf '.'; sleep 1; done
  done
fi

start_delay=$((30*($node_id-1)))
if [[ $start_delay != 0 ]]; then
  echo "### Waiting $start_delay seconds prior starting Elasticsearch..."
  sleep $start_delay
fi

echo "### Enabling and starting Elasticsearch..."

systemctl enable elasticsearch
systemctl start elasticsearch
