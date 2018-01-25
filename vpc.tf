# @author: Alejandro Galue <agalue@opennms.org>

resource "aws_vpc" "default" {
    cidr_block           = "${var.vpc_cidr}"
    enable_dns_hostnames = true
    enable_dns_support   = true

    tags {
        Name = "Terraform VPC"
    }
}

data "aws_availability_zones" "available" {}

# Internet Gateway

resource "aws_internet_gateway" "default" {
    vpc_id = "${aws_vpc.default.id}"

    tags {
        Name = "Terraform IG"
    }
}

# Public Subnet

resource "aws_subnet" "public" {
    vpc_id            = "${aws_vpc.default.id}"
    cidr_block        = "${var.public_subnet_cidr}"
    availability_zone = "${data.aws_availability_zones.available.names[0]}"

    tags {
        Name = "Terraform Public Subnet (Zone ${count.index + 1})",
    }
}

resource "aws_route_table" "gw" {
    vpc_id = "${aws_vpc.default.id}"

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${aws_internet_gateway.default.id}"
    }

    tags {
        Name = "Terraform Routing Public Subnet"
    }
}

resource "aws_route_table_association" "public" {
    subnet_id      = "${aws_subnet.public.id}"
    route_table_id = "${aws_route_table.gw.id}"
}

# DNS

resource "aws_vpc_dhcp_options" "main" {
    domain_name         = "${var.dns_zone}"
    domain_name_servers = ["AmazonProvidedDNS"]

    tags {
        Name = "Terraform Internal Name"
    }
}

resource "aws_vpc_dhcp_options_association" "main" {
    vpc_id          = "${aws_vpc.default.id}"
    dhcp_options_id = "${aws_vpc_dhcp_options.main.id}"
}

resource "aws_route53_zone" "main" {
    name    = "${var.dns_zone}"
    vpc_id  = "${aws_vpc.default.id}"
    comment = "Manabed by Terraform"
}