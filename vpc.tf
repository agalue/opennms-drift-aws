# @author: Alejandro Galue <agalue@opennms.org>

resource "aws_vpc" "default" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "Terraform VPC"
    Environment = "Test"
    Department  = "Support"
  }
}

data "aws_availability_zones" "available" {
}

# Internet Gateway

resource "aws_internet_gateway" "default" {
  vpc_id = aws_vpc.default.id

  tags = {
    Name        = "Terraform IG"
    Environment = "Test"
    Department  = "Support"
  }
}

# Subnets

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.default.id
  cidr_block        = var.public_subnet_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name        = "Terraform Public Subnet"
    Environment = "Test"
    Department  = "Support"
  }
}

resource "aws_route_table" "gw" {
  vpc_id = aws_vpc.default.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.default.id
  }

  tags = {
    Name        = "Terraform Routing Public Subnet"
    Environment = "Test"
    Department  = "Support"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.gw.id
}

# DNS

resource "aws_vpc_dhcp_options" "main" {
  domain_name         = aws_route53_zone.private.name
  domain_name_servers = ["AmazonProvidedDNS"]

  tags = {
    Name        = "Terraform Internal Name"
    Environment = "Test"
    Department  = "Support"
  }
}

resource "aws_vpc_dhcp_options_association" "main" {
  vpc_id          = aws_vpc.default.id
  dhcp_options_id = aws_vpc_dhcp_options.main.id
}

data "aws_route53_zone" "parent" {
  name = var.parent_dns_zone
}

resource "aws_route53_zone" "main" {
  name = var.dns_zone
}

resource "aws_route53_record" "main-ns" {
  zone_id = data.aws_route53_zone.parent.zone_id
  name    = aws_route53_zone.main.name
  type    = "NS"
  ttl     = var.dns_ttl
  records = [
    aws_route53_zone.main.name_servers[0],
    aws_route53_zone.main.name_servers[1],
    aws_route53_zone.main.name_servers[2],
    aws_route53_zone.main.name_servers[3],
  ]
}

resource "aws_route53_zone" "private" {
  name   = var.dns_zone_private
  vpc_id = aws_vpc.default.id
}

