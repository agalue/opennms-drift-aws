# @author: Alejandro Galue <agalue@opennms.org>

# Region

variable "aws_region" {
  description = "EC2 Region for the VPC"
  default     = "us-east-2" # For testing purposes only (should be changed)
}

# Access (make sure to use your own keys)

variable "aws_key_name" {
  description = "AWS Key Name, to access EC2 instances through SSH"
  default     = "agalue" # For testing purposes only (should be changed, based on aws_region)
}

variable "aws_private_key" {
  description = "AWS Private Key Full Path"
  default     = "/Users/agalue/.ssh/agalue.private.aws.us-east-2.pem" # For testing purposes only (should be changed, based on aws_region)
}

# DNS

variable "parent_dns_zone" {
  description = "Parent DNS Zone Name"
  default     = "opennms.org" # For testing purposes only (should be changed)
}

variable "dns_zone" {
  description = "Public DNS Zone Name"
  default     = "aws.opennms.org" # For testing purposes only (should be changed, based on parent_dns_zone)
}

variable "dns_zone_private" {
  description = "Private DNS Zone Name"
  default     = "terraform.local"
}

variable "dns_ttl" {
  description = "DNS TTL"
  default     = 60
}

# Make sure to run Packer on the same region

data "aws_ami" "cassandra" {
  most_recent = true

  filter {
    name   = "name"
    values = ["scylladb-*"]
  }
}

data "aws_ami" "elasticsearch" {
  most_recent = true

  filter {
    name   = "name"
    values = ["elasticsearch-*"]
  }
}

data "aws_ami" "kafka" {
  most_recent = true

  filter {
    name   = "name"
    values = ["kafka-*"]
  }
}

data "aws_ami" "kibana" {
  most_recent = true

  filter {
    name   = "name"
    values = ["kibana-*"]
  }
}

data "aws_ami" "opennms" {
  most_recent = true

  filter {
    name   = "name"
    values = ["opennms-horizon-23-*"]
  }
}

data "aws_ami" "sentinel" {
  most_recent = true

  filter {
    name   = "name"
    values = ["opennms-sentinel-*"]
  }
}

data "aws_ami" "postgresql" {
  most_recent = true

  filter {
    name   = "name"
    values = ["postgresql-*"]
  }
}

# Minimum requirements are: 2GB of RAM and 2 CPUs.
# https://www.datastax.com/dev/blog/ec2-series-doc

variable "instance_types" {
  description = "Instance types per server/application"
  type        = "map"

  default = {
    onms_core      = "t2.large"
    onms_sentinel  = "t2.large"
    onms_ui        = "t2.medium"
    postgresql     = "t2.medium"
    es_master      = "t2.small"
    es_data        = "t2.medium"
    kibana         = "t2.medium"
    kafka          = "t2.medium"
    zookeeper      = "t2.medium"
    cassandra      = "t2.medium"
  }
}

# Networks

# This is a proof of concept, so everything will be on a single availability zone,
# with direct internet access, so instances might have public IP addresses.

variable "vpc_cidr" {
  description = "CIDR for the whole VPC"
  default     = "172.16.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR for the public subnet"
  default     = "172.16.1.0/24"
}

# Application IP Addresses

# This is a master/slave configuration, so change this carefully.
variable "pg_ip_addresses" {
  description = "PostgreSQL Servers Private IPs"
  type        = "map"

  default = {
    postgresql1 = "172.16.1.101"
    postgresql2 = "172.16.1.102"
  }
}

# This is a master/slave configuration, so change this carefully.
variable "pg_roles" {
  description = "PostgreSQL server roles: master or slave"
  type        = "list"

  # Declare the sibling based on the key order defined for pg_ip_addresses
  default = [
    "master",
    "slave",
  ]
}

# There should be only one OpenNMS server
variable "onms_ip_addresses" {
  description = "OpenNMS Servers Private IPs"
  type        = "map"

  default = {
    onmscore = "172.16.1.100"
  }
}

variable "onms_sentinel_ip_addresses" {
  description = "OpenNMS Sentinel Servers Private IPs"
  type        = "map"

  default = {
    sentinel1 = "172.16.1.81"
    sentinel2 = "172.16.1.82"
  }
}

variable "onms_ui_ip_addresses" {
  description = "OpenNMS UI Servers Private IPs"
  type        = "map"

  default = {
    onmsui1 = "172.16.1.71"
    onmsui2 = "172.16.1.72"
  }
}

# There should be only 3 Zookeeper servers
variable "zookeeper_ip_addresses" {
  description = "Zookeeper Servers Private IPs"
  type        = "map"

  default = {
    zookeeper1 = "172.16.1.21"
    zookeeper2 = "172.16.1.22"
    zookeeper3 = "172.16.1.23"
  }
}

variable "kafka_ip_addresses" {
  description = "Kafka Servers Private IPs"
  type        = "map"

  default = {
    kafka1 = "172.16.1.31"
    kafka2 = "172.16.1.32"
    kafka3 = "172.16.1.33"
  }
}

variable "cassandra_ip_addresses" {
  description = "Cassandra Servers Private IPs"
  type        = "map"

  default = {
    cassandra1 = "172.16.1.41"
    cassandra2 = "172.16.1.42"
    cassandra3 = "172.16.1.43"
  }
}

# There should be only 3 ES master servers
variable "es_master_ip_addresses" {
  description = "Elasticsearch Master Servers Private IPs"
  type        = "map"

  default = {
    esmaster1 = "172.16.1.51"
    esmaster2 = "172.16.1.52"
    esmaster3 = "172.16.1.53"
  }
}

variable "es_data_ip_addresses" {
  description = "Elasticsearch Data Servers Private IPs"
  type        = "map"

  default = {
    esdata1 = "172.16.1.54"
    esdata2 = "172.16.1.55"
    esdata3 = "172.16.1.56"
  }
}

variable "kibana_ip_addresses" {
  description = "Kibana Servers Private IPs"
  type        = "map"

  default = {
    kibana = "172.16.1.60"
  }
}

# For the number of partitions in kafka, keep in mind OpenNMS defaults:
# - 2 times the amount of cores of the OpenNMS instance.
#
# To tune the number of threads, check:
# - trapd-configuration.xml
# - syslogd-configuration.xml
# - telemetryd-configurtaion.xml
#
# The minimum in-sync replicas should be less than or equal to the
# replication factor. If it is equal, keep in mind that the number
# of nodes should be big enough to accomodate loosing nodes.
#
# The replication factor should be less than the number of nodes,
# in Kafka and Cassandra.

variable "settings" {
  description = "Common application settings"
  type        = "map"

  default = {
    cluster_name                 = "OpenNMS-Cluster"
    kafka_num_partitions         = 32
    kafka_replication_factor     = 2
    kafka_min_insync_replicas    = 1
    kafka_security_protocol      = "SASL_PLAINTEXT" # To disable SASL, use "PLAINTEXT"
    kafka_security_mechanisms    = "PLAIN,SCRAM-SHA-256"
    kafka_client_mechanism       = "PLAIN" # SCRAM-SHA-256
    kafka_security_module        = "org.apache.kafka.common.security.plain.PlainLoginModule" # org.apache.kafka.common.security.scram.ScramLoginModule
    kafka_admin_password         = "0p3nNMS"
    kafka_user_name              = "opennms"
    kafka_user_password          = "0p3nNMS"
    kafka_max_message_size       = 5242880
    rpc_ttl                      = 300000
    cassandra_datacenter         = "AWS"
    cassandra_replication_factor = 2
    postgresql_version_family    = "10-2"
    postgresql_max_connections   = 300
    postgresql_password          = "0p3nNMS"
    postgresql_opennms_password  = "0p3nNMS"
    elastic_user                 = "elastic" # This is the default user, do not change it
    elastic_password             = "opennms"
    elastic_license              = "trial" # Use 'basic' or 'trial'. The last one requires proper authentication configured.
    elastic_flow_index_strategy  = "hourly"
    onms_use_30sec_frequency     = "true"
  }
}

variable "disk_space" {
  description = "Disk space per node (per application) in GB"
  type        = "map"

  default = {
    elasticsearch = "100"
    kafka         = "100"
    zookeeper     = "20"
    postgresql    = "100"
    cassandra     = "100"
  }
}
