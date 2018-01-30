# @author: Alejandro Galue <agalue@opennms.org>

resource "aws_security_group" "common" {
    name = "terraform-opennms-common-sq"
    description = "Allow basic protocols"

    ingress {
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port   = 161
        to_port     = 161
        protocol    = "udp"
        cidr_blocks = ["${var.vpc_cidr}"]
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

    vpc_id = "${aws_vpc.default.id}"

    tags {
        Name = "Terraform Common SG"
    }
}

resource "aws_security_group" "activemq" {
    name = "terraform-opennms-activemq-sg"
    description = "Allow ActiveMQ connections."

    ingress {
        from_port   = 61616
        to_port     = 61616
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port   = 8161
        to_port     = 8161
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    vpc_id = "${aws_vpc.default.id}"

    tags {
        Name = "Terraform ActiveMQ SG"
    }
}

resource "aws_security_group" "zookeeper" {
    name = "terraform-opennms-zookeeper-sg"
    description = "Allow Zookeeper connections."

    ingress {
        from_port   = 2181
        to_port     = 2181
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port   = 2888
        to_port     = 2888
        protocol    = "tcp"
        cidr_blocks = ["${var.vpc_cidr}"]
    }

    ingress {
        from_port   = 3888
        to_port     = 3888
        protocol    = "tcp"
        cidr_blocks = ["${var.vpc_cidr}"]
    }

    ingress {
        from_port   = 9998
        to_port     = 9998
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    vpc_id = "${aws_vpc.default.id}"

    tags {
        Name = "Terraform Zookeeper SG"
    }
}

resource "aws_security_group" "kafka" {
    name = "terraform-opennms-kafka-sg"
    description = "Allow Kafka connections."

    ingress {
        from_port   = 9092
        to_port     = 9092
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port   = 9999
        to_port     = 9999
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    vpc_id = "${aws_vpc.default.id}"

    tags {
        Name = "Terraform Kafka SG"
    }
}

resource "aws_security_group" "cassandra" {
    name = "terraform-opennms-cassandra-sg"
    description = "Allow Cassandra connections."

    ingress {
        from_port   = 7199
        to_port     = 7199
        protocol    = "tcp"
        cidr_blocks = ["${var.vpc_cidr}"]
    }

    ingress {
        from_port   = 7000
        to_port     = 7001
        protocol    = "tcp"
        cidr_blocks = ["${var.vpc_cidr}"]
    }

    ingress {
        from_port   = 9042
        to_port     = 9042
        protocol    = "tcp"
        cidr_blocks = ["${var.vpc_cidr}"]
    }

    ingress {
        from_port   = 9160
        to_port     = 9160
        protocol    = "tcp"
        cidr_blocks = ["${var.vpc_cidr}"]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    vpc_id = "${aws_vpc.default.id}"

    tags {
        Name = "Terraform Cassandra SG"
    }
}

resource "aws_security_group" "postgresql" {
    name = "terraform-opennms-postgresql-sg"
    description = "Allow PostgreSQL connections."

    ingress {
        from_port   = 5432
        to_port     = 5432
        protocol    = "tcp"
        cidr_blocks = ["${var.vpc_cidr}"]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    vpc_id = "${aws_vpc.default.id}"

    tags {
        Name = "Terraform PostgreSQL SG"
    }
}

resource "aws_security_group" "elasticsearch" {
    name = "terraform-opennms-elasticsearch-sg"
    description = "Allow Elasticsearch connections."

    ingress {
        from_port   = 9200
        to_port     = 9200
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port   = 9300
        to_port     = 9300
        protocol    = "tcp"
        cidr_blocks = ["${var.vpc_cidr}"]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    vpc_id = "${aws_vpc.default.id}"

    tags {
        Name = "Terraform Elasticsearch SG"
    }
}

resource "aws_security_group" "kibana" {
    name = "terraform-opennms-kibana-sg"
    description = "Allow Kibana connections."

    ingress {
        from_port   = 5601
        to_port     = 5601
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    vpc_id = "${aws_vpc.default.id}"

    tags {
        Name = "Terraform Kibana SG"
    }
}

resource "aws_security_group" "opennms" {
    name = "terraform-opennms-sg"
    description = "Allow OpenNMS connections."

    ingress {
        from_port   = 8980
        to_port     = 8980
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port   = 18980
        to_port     = 18980
        protocol    = "tcp"
        cidr_blocks = ["${var.vpc_cidr}"]
    }

    ingress { # NFS
        from_port   = 2049
        to_port     = 2049
        protocol    = "tcp"
        cidr_blocks = ["${var.vpc_cidr}"]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    vpc_id = "${aws_vpc.default.id}"

    tags {
        Name = "Terraform OpenNMS UI SG"
    }
}

resource "aws_security_group" "opennms_ui" {
    name = "terraform-opennms-ui-sg"
    description = "Allow OpenNMS connections."

    ingress {
        from_port   = 80
        to_port     = 80
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port   = 8980
        to_port     = 8980
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port   = 3000
        to_port     = 3000
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    vpc_id = "${aws_vpc.default.id}"

    tags {
        Name = "Terraform OpenNMS UI SG"
    }
}

resource "aws_security_group" "grafana" {
    name = "terraform-opennms-grafana-sg"
    description = "Allow Grafana connections."

    ingress {
        from_port   = 3000
        to_port     = 3000
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    vpc_id = "${aws_vpc.default.id}"

    tags {
        Name = "Terraform Grafana UI SG"
    }
}