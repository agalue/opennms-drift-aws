# @author: Alejandro Galue <agalue@opennms.org>

# Access (make sure to use your own keys)

variable "aws_key_name"  {
    description = "AWS Key Name, to access EC2 instances through SSH"
    default = "agalue" # For testing purposes only
}

variable "aws_private_key" {
    description = "AWS Private Key Full Path"
    default = "/Users/agalue/.ssh/agalue.private.aws.us-east-2.pem" # For testing purposes only
}

# Region and AMIs

variable "aws_region" {
    description = "EC2 Region for the VPC"
    default = "us-east-2" # For testing purposes only
}

variable "aws_amis" {  # Amazon Linux 2 LT SCandidate AMI 2017.12.0
    description = "AMIs by region"
    type = "map"

    default = {
        us-east-1 = "ami-428aa838"
        us-east-2 = "ami-710e2414"
        us-west-1 = "ami-4a787a2a"
        us-west-2 = "ami-7f43f307"
    }
}

variable "instance_types" {
    description = "Instance types per server/application"
    type = "map"

    default = {
        opennms       = "t2.large"
        postgresql    = "t2.medium"
        elasticsearch = "t2.medium"
        kibana        = "t2.medium"
        activemq      = "t2.medium"
        kafka         = "t2.medium"
        zookeeper     = "t2.medium"
        cassandra     = "t2.medium"
    }
}

# Networks

# This is a proof of concept, so everything will be on a sincle availability zone
# with direct internet access, so instances might have public IP addresses.

variable "dns_zone" {
    description = "Internal DNS Zone Name"
    default = "terraform.opennms.local"
}

variable "vpc_cidr" {
    description = "CIDR for the whole VPC"
    default = "172.16.0.0/16"
}

variable "public_subnet_cidr" {
    description = "CIDR for the public subnet"
    default = "172.16.1.0/24"
}

variable "pg_ip_addresses" {
    description = "PostgreSQL Servers Private IPs"
    type = "map"

    default = {
        postgresql = "172.16.1.101"
    }
}

variable "onms_ip_addresses" {
    description = "OpenNMS Servers Private IPs"
    type = "map"

    default = {
        opennms = "172.16.1.100"
    }
}

variable "onms_ui_ip_addresses" {
    description = "OpenNMS UI Servers Private IPs"
    type = "map"

    default = {
        onmsui1 = "172.16.1.71"
        onmsui2 = "172.16.1.72"
    }
}

variable "amq_ip_addresses" {
    description = "ActiveMQ IP Pair: 2 instances working on a Network of Brokers config, for failover"
    type = "map"

    default = {
        activemq1 = "172.16.1.11"
        activemq2 = "172.16.1.12"
    }
}

variable "amq_siblings" {
    description = "ActiveMQ IP Sibling Pair: the inverse of amq_ip_addresses"
    type = "list"

    default = [
        "activemq2",
        "activemq1"
    ]
}

variable "zookeeper_ip_addresses" {
    description = "Zookeeper Servers Private IPs"
    type = "map"

    default = {
        zookeeper1 = "172.16.1.21"
        zookeeper2 = "172.16.1.22"
        zookeeper3 = "172.16.1.23"
    }
}

variable "kafka_ip_addresses" {
    description = "Kafka Servers Private IPs"
    type = "map"

    default = {
        kafka1 = "172.16.1.31"
        kafka2 = "172.16.1.32"
        kafka3 = "172.16.1.33"
    }
}

variable "cassandra_ip_addresses" {
    description = "Cassandra Servers Private IPs"
    type = "map"

    default = {
        cassandra1 = "172.16.1.41"
        cassandra2 = "172.16.1.42"
        cassandra3 = "172.16.1.43"
    }
}

variable "es_ip_addresses" {
    description = "Eslasticsearch Servers Private IPs"
    type = "map"

    default = {
        elasticsearch1 = "172.16.1.51"
        elasticsearch2 = "172.16.1.52"
        elasticsearch3 = "172.16.1.53"
    }
}

variable "kibana_ip_addresses" {
    description = "Kibana Servers Private IPs"
    type = "map"

    default = {
        kibana = "172.16.1.60"
    }
}

# Applications

variable "versions" {
    description = "Versions for the external dependencies"
    type = "map"

    default = {
        elasticsearch   = "6.2.1"
        activemq        = "5.13.5"
        kafka           = "1.0.0"
        scala           = "2.12"
        zookeeper       = "3.4.11"
        postgresql_repo = "9.6-3"
        cassandra_repo  = "311x"
        onms_repo       = "branches-features-drift"
        onms_version    = "-latest-"
    }
}

# For the number of partitions in kafka, keep in mind OpenNMS defaults:
# 2 times the amount of cores of the OpenNMS instance.
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
# in Kafka and Cassandra

variable "settings" {
    description = "Common application settings"
    type = "map"

    default = {
        cluster_name = "OpenNMS-Cluster"
        kafka_num_partitions = 16
        kafka_replication_factor  = 2
        kafka_min_insync_replicas = 1
        cassandra_replication_factor = 2
    }
}