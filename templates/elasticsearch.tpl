#!/bin/bash
# Author: Alejandro Galue <agalue@opennms.org>
# Warning: This is intended to be used through Terraform's template plugin only

# AWS Template Variables
# - node_id
# - vpc_cidr
# - hostname
# - domainname
# - es_version
# - es_cluster_name
# - es_seed_name
# - es_password

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

echo "### Downloading and installing Oracle JDK..."

java_url="http://download.oracle.com/otn-pub/java/jdk/8u161-b12/2f38c3b165be4555a1fa6e98c45e0808/jdk-8u161-linux-x64.rpm"
java_rpm=/tmp/jdk8-linux-x64.rpm
wget -c --quiet --header "Cookie: oraclelicense=accept-securebackup-cookie" -O $java_rpm $java_url
if [ ! -s $java_rpm ]; then
  echo "FATAL: Cannot download Java from $java_url. Using OpenNMS default ..."
  yum install -y -q http://yum.opennms.org/repofiles/opennms-repo-stable-rhel7.noarch.rpm
  rpm --import /etc/yum.repos.d/opennms-repo-stable-rhel7.gpg
  yum install -y -q jdk1.8.0_144
  yum erase -y -q opennms-repo-stable
else
  yum install -y -q $java_rpm
  rm -f $java_rpm
fi

echo "### Downloading and installing Elasticsearch..."

yum install -y -q https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-${es_version}.rpm
/usr/share/elasticsearch/bin/elasticsearch-plugin install --batch x-pack

echo "### Configuring Elasticsearch..."

es_dir=/etc/elasticsearch
es_yaml=$es_dir/elasticsearch.yml
cp $es_yaml $es_yaml.bak

ip_address=`curl http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null`

sed -i -r "s/[#]?cluster.name:.*/cluster.name: ${es_cluster_name}/" $es_yaml
sed -i -r "s/[#]?network.host:.*/network.host: $ip_address/" $es_yaml
sed -i -r "s/[#]?node.name:.*/node.name: ${hostname}/" $es_yaml
sed -i -r "s/[#]?discovery.zen.minimum_master_nodes:.*/discovery.zen.minimum_master_nodes: 1/" $es_yaml
sed -i -r "s/[#]?discovery.zen.ping.unicast.hosts:.*/discovery.zen.ping.unicast.hosts: [\"${es_seed_name}\"]/" $es_yaml

echo ${es_password} | /usr/share/elasticsearch/bin/elasticsearch-keystore add -x 'bootstrap.password'

echo "### Checking cluster prior start..."

start_delay=$((60*(${node_id}-1)))
if [[ $start_delay != 0 ]]; then
  es_url=http://${es_seed_name}:9200
  until $$(curl --output /dev/null --silent --head --fail -u "elastic:${es_password}" $es_url); do
    printf '.'
    sleep 5
  done
  echo "### Waiting $start_delay seconds prior starting Elasticsearch..."
  sleep $start_delay
fi

echo "### Enabling and starting Elasticsearch..."

systemctl enable elasticsearch
systemctl start elasticsearch
