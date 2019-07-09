# @author: Alejandro Galue <agalue@opennms.org>

data "template_file" "postgresql" {
  count    = length(var.pg_ip_addresses)
  template = file("${path.module}/templates/postgresql.tpl")

  vars = {
    node_id            = count.index + 1
    vpc_cidr           = var.vpc_cidr
    hostname           = element(keys(var.pg_ip_addresses), count.index)
    domainname         = aws_route53_zone.private.name
    pg_max_connections = var.settings["postgresql_max_connections"]
    pg_version_family  = var.settings["postgresql_version_family"]
    pg_role            = element(var.pg_roles, count.index)
    pg_rep_slots       = length(var.pg_ip_addresses) + 1
    pg_master_server   = element(keys(var.pg_ip_addresses), 0)
  }
}

resource "aws_instance" "postgresql" {
  count         = length(var.pg_ip_addresses)
  ami           = data.aws_ami.postgresql.image_id
  instance_type = var.instance_types["postgresql"]
  subnet_id     = aws_subnet.public.id
  key_name      = var.aws_key_name
  private_ip    = element(values(var.pg_ip_addresses), count.index)
  user_data     = element(data.template_file.postgresql.*.rendered, count.index)

  associate_public_ip_address = true

  vpc_security_group_ids = [
    aws_security_group.common.id,
    aws_security_group.postgresql.id,
  ]

  root_block_device {
    volume_type = "gp2"
    volume_size = var.disk_space["postgresql"]
  }

  depends_on = [aws_route53_record.postgresql_private]

  connection {
    host        = coalesce(self.public_ip, self.private_ip)
    type        = "ssh"
    user        = "ec2-user"
    private_key = file(var.aws_private_key)
  }

  timeouts {
    create = "30m"
    delete = "15m"
  }

  tags = {
    Name        = "Terraform PostgreSQL Server ${count.index + 1}"
    Environment = "Test"
    Department  = "Support"
  }
}

resource "aws_route53_record" "postgresql" {
  count   = length(var.pg_ip_addresses)
  zone_id = aws_route53_zone.main.zone_id
  name    = "${element(keys(var.pg_ip_addresses), count.index)}.${aws_route53_zone.main.name}"
  type    = "A"
  ttl     = var.dns_ttl
  records = [
    element(aws_instance.postgresql.*.public_ip, count.index),
  ]
}

resource "aws_route53_record" "postgresql_private" {
  count   = length(var.pg_ip_addresses)
  zone_id = aws_route53_zone.private.zone_id
  name    = "${element(keys(var.pg_ip_addresses), count.index)}.${aws_route53_zone.private.name}"
  type    = "A"
  ttl     = var.dns_ttl
  # TF-UPGRADE-TODO: In Terraform v0.10 and earlier, it was sometimes necessary to
  # force an interpolation expression to be interpreted as a list by wrapping it
  # in an extra set of list brackets. That form was supported for compatibilty in
  # v0.11, but is no longer supported in Terraform v0.12.
  #
  # If the expression in the following list itself returns a list, remove the
  # brackets to avoid interpretation as a list of lists. If the expression
  # returns a single list item then leave it as-is and remove this TODO comment.
  records = [
    element(values(var.pg_ip_addresses), count.index),
  ]
}

output "postgresql" {
  value = join(",", aws_instance.postgresql.*.public_ip)
}

