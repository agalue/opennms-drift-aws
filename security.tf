# @author: Alejandro Galue <agalue@opennms.org>

resource "aws_security_group" "common" {
  name        = "terraform-opennms-common-sq"
  description = "Allow basic protocols"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    description = "SSH"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 161
    to_port     = 161
    protocol    = "udp"
    description = "SNMP"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  vpc_id = aws_vpc.default.id

  tags = {
    Name        = "Terraform Common SG"
    Environment = "Test"
    Department  = "Support"
  }
}

resource "aws_security_group" "zookeeper" {
  name        = "terraform-opennms-zookeeper-sg"
  description = "Allow Zookeeper connections."

  ingress {
    from_port   = 2181
    to_port     = 2181
    protocol    = "tcp"
    description = "Clients"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    from_port   = 2888
    to_port     = 2888
    protocol    = "tcp"
    description = "Peer"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    from_port   = 3888
    to_port     = 3888
    protocol    = "tcp"
    description = "Leader Election"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    from_port   = 9998
    to_port     = 9998
    protocol    = "tcp"
    description = "JMX"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  vpc_id = aws_vpc.default.id

  tags = {
    Name        = "Terraform Zookeeper SG"
    Environment = "Test"
    Department  = "Support"
  }
}

resource "aws_security_group" "kafka" {
  name        = "terraform-opennms-kafka-sg"
  description = "Allow Kafka connections."

  ingress {
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    description = "Clients"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 9999
    to_port     = 9999
    protocol    = "tcp"
    description = "JMX"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  vpc_id = aws_vpc.default.id

  tags = {
    Name        = "Terraform Kafka SG"
    Environment = "Test"
    Department  = "Support"
  }
}

resource "aws_security_group" "cassandra" {
  name        = "terraform-opennms-cassandra-sg"
  description = "Allow Cassandra connections."

  ingress {
    from_port   = 7199
    to_port     = 7199
    protocol    = "tcp"
    description = "JMX"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    from_port   = 7000
    to_port     = 7001
    protocol    = "tcp"
    description = "Intra Node"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    from_port   = 9042
    to_port     = 9042
    protocol    = "tcp"
    description = "CQL Native"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    from_port   = 9160
    to_port     = 9160
    protocol    = "tcp"
    description = "Thrift"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  vpc_id = aws_vpc.default.id

  tags = {
    Name        = "Terraform Cassandra SG"
    Environment = "Test"
    Department  = "Support"
  }
}

resource "aws_security_group" "postgresql" {
  name        = "terraform-opennms-postgresql-sg"
  description = "Allow PostgreSQL connections."

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    description = "Clients"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  vpc_id = aws_vpc.default.id

  tags = {
    Name        = "Terraform PostgreSQL SG"
    Environment = "Test"
    Department  = "Support"
  }
}

resource "aws_security_group" "elasticsearch" {
  name        = "terraform-opennms-elasticsearch-sg"
  description = "Allow Elasticsearch connections."

  ingress {
    from_port   = 9200
    to_port     = 9200
    protocol    = "tcp"
    description = "HTTP"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    from_port   = 9300
    to_port     = 9300
    protocol    = "tcp"
    description = "Transport"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  vpc_id = aws_vpc.default.id

  tags = {
    Name        = "Terraform Elasticsearch SG"
    Environment = "Test"
    Department  = "Support"
  }
}

resource "aws_security_group" "kibana" {
  name        = "terraform-opennms-kibana-sg"
  description = "Allow Kibana connections."

  ingress {
    from_port   = 5601
    to_port     = 5601
    protocol    = "tcp"
    description = "HTTP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  vpc_id = aws_vpc.default.id

  tags = {
    Name        = "Terraform Kibana SG"
    Environment = "Test"
    Department  = "Support"
  }
}

resource "aws_security_group" "opennms" {
  name        = "terraform-opennms-sg"
  description = "Allow OpenNMS Core connections."

  ingress {
    from_port   = 8980
    to_port     = 8980
    protocol    = "tcp"
    description = "HTTP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 18980
    to_port     = 18980
    protocol    = "tcp"
    description = "JMX"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    description = "Redis"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    from_port   = 8101
    to_port     = 8101
    protocol    = "tcp"
    description = "Karaf SSH"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  vpc_id = aws_vpc.default.id

  tags = {
    Name        = "Terraform OpenNMS Core SG"
    Environment = "Test"
    Department  = "Support"
  }
}

resource "aws_security_group" "sentinel" {
  name        = "terraform-sentinel-sg"
  description = "Allow Sentinel connections."

  ingress {
    from_port   = 5005
    to_port     = 5005
    protocol    = "tcp"
    description = "Karaf Debug"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    from_port   = 8301
    to_port     = 8301
    protocol    = "tcp"
    description = "Karaf SSH"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8181
    to_port     = 8181
    protocol    = "tcp"
    description = "Hawtio WebUI"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  vpc_id = aws_vpc.default.id

  tags = {
    Name        = "Terraform Sentinel SG"
    Environment = "Test"
    Department  = "Support"
  }
}

resource "aws_security_group" "opennms_ui" {
  name        = "terraform-opennms-ui-sg"
  description = "Allow OpenNMS UI connections."

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    description = "HTTP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 18980
    to_port     = 18980
    protocol    = "tcp"
    description = "JMX"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    from_port   = 8101
    to_port     = 8101
    protocol    = "tcp"
    description = "Karaf SSH"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  vpc_id = aws_vpc.default.id

  tags = {
    Name        = "Terraform OpenNMS UI SG"
    Environment = "Test"
    Department  = "Support"
  }
}

