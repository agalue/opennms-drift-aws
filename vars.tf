# @author: Alejandro Galue <agalue@opennms.org>

# Access (make sure to use your own keys)

variable "aws_key_name" {
  description = "AWS Key Name, to access EC2 instances through SSH"
  default     = "agalue"                                            # For testing purposes only
}

variable "aws_private_key" {
  description = "AWS Private Key Full Path"
  default     = "/Users/agalue/.ssh/agalue.private.aws.us-east-2.pem" # For testing purposes only
}

# Region and AMIs
# Make sure to run Packer on the same region

variable "aws_region" {
  description = "EC2 Region for the VPC"
  default     = "us-east-2"              # For testing purposes only
}

data "aws_ami" "activemq" {
  most_recent = true

  filter {
    name   = "name"
    values = ["activemq-*"]
  }
}

data "aws_ami" "cassandra" {
  most_recent = true

  filter {
    name   = "name"
    values = ["cassandra-*"]
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
    values = ["opennms-*"]
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
    onms_core  = "t2.large"
    onms_ui    = "t2.medium"
    postgresql = "t2.medium"
    es_master  = "t2.small"
    es_data    = "t2.medium"
    kibana     = "t2.medium"
    activemq   = "t2.medium"
    kafka      = "t2.medium"
    zookeeper  = "t2.medium"
    cassandra  = "t2.medium"
  }
}

# Networks

# This is a proof of concept, so everything will be on a single availability zone,
# with direct internet access, so instances might have public IP addresses.

variable "dns_zone" {
  description = "Internal DNS Zone Name"
  default     = "terraform.opennms.local"
}

variable "vpc_cidr" {
  description = "CIDR for the whole VPC"
  default     = "172.16.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR for the public subnet"
  default     = "172.16.1.0/24"
}

variable "elb_subnet_cidr" {
  description = "CIDR for the ELB subnet"
  default     = "172.16.2.0/24"
}

# Application IP Addresses

variable "pg_ip_addresses" {
  description = "PostgreSQL Servers Private IPs"
  type        = "map"

  default = {
    postgresql1 = "172.16.1.101"
    postgresql2 = "172.16.1.102"
  }
}

variable "pg_roles" {
  description = "PostgreSQL server roles: master or slave"
  type        = "list"

  # Declare the sibling based on the key order defined for pg_ip_addresses
  default = [
    "master",
    "slave",
  ]
}

variable "onms_ip_addresses" {
  description = "OpenNMS Servers Private IPs"
  type        = "map"

  default = {
    opennms = "172.16.1.100"
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

variable "amq_ip_addresses" {
  description = "ActiveMQ IP Pair: 2 instances working on a Network of Brokers config, for failover"
  type        = "map"

  default = {
    activemq1 = "172.16.1.11"
    activemq2 = "172.16.1.12"
  }
}

variable "amq_siblings" {
  description = "ActiveMQ IP Sibling Pair: the inverse of amq_ip_addresses"
  type        = "list"

  # Declare the sibling based on the key order defined for amq_ip_addresses
  default = [
    "activemq2",
    "activemq1",
  ]
}

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
    kafka_num_partitions         = 16
    kafka_replication_factor     = 2
    kafka_min_insync_replicas    = 1
    cassandra_replication_factor = 2
    postgresql_version_family    = "9.6-3"
    postgresql_max_connections   = 200
    elastic_password             = "opennms"
    elastic_flow_index_strategy  = "hourly"
    onms_use_30sec_frequency     = "true"
  }
}

variable "disk_space" {
  description = "Disk space per node (per application) in GB"
  type        = "map"

  default = {
    elasticsearch = "100"
    activemq      = "100"
    kafka         = "100"
    zookeeper     = "8"
    postgresql    = "100"
    cassandra     = "100"
  }
}
