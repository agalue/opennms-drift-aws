# @author: Alejandro Galue <agalue@opennms.org>

data "template_file" "cassandra" {
  count    = length(var.cassandra_ip_addresses)
  template = file("${path.module}/templates/cassandra.tpl")

  vars = {
    node_id      = count.index + 1
    hostname     = element(keys(var.cassandra_ip_addresses), count.index)
    domainname   = aws_route53_zone.private.name
    cluster_name = var.settings["cluster_name"]
    seed_name    = element(aws_route53_record.cassandra_private.*.name, 0)
    datacenter   = var.settings["cassandra_datacenter"]
    rack         = "Rack${count.index + 1}"
  }
}

resource "aws_instance" "cassandra" {
  count         = length(var.cassandra_ip_addresses)
  ami           = data.aws_ami.cassandra.image_id
  instance_type = var.instance_types["cassandra"]
  subnet_id     = aws_subnet.public.id
  key_name      = var.aws_key_name
  private_ip    = element(values(var.cassandra_ip_addresses), count.index)
  user_data     = element(data.template_file.cassandra.*.rendered, count.index)

  associate_public_ip_address = true

  vpc_security_group_ids = [
    aws_security_group.common.id,
    aws_security_group.cassandra.id,
  ]

  root_block_device {
    volume_type = "gp2"
    volume_size = var.disk_space["cassandra"]
  }

  depends_on = [aws_route53_record.cassandra_private]

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
    Name        = "Terraform Cassandra Server ${count.index + 1}"
    Environment = "Test"
    Department  = "Support"
  }
}

resource "aws_route53_record" "cassandra" {
  count   = length(var.cassandra_ip_addresses)
  zone_id = aws_route53_zone.main.zone_id
  name    = "${element(keys(var.cassandra_ip_addresses), count.index)}.${aws_route53_zone.main.name}"
  type    = "A"
  ttl     = var.dns_ttl
  records = [
    element(aws_instance.cassandra.*.public_ip, count.index),
  ]
}

resource "aws_route53_record" "cassandra_private" {
  count   = length(var.cassandra_ip_addresses)
  zone_id = aws_route53_zone.private.zone_id
  name    = "${element(keys(var.cassandra_ip_addresses), count.index)}.${aws_route53_zone.private.name}"
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
    element(values(var.cassandra_ip_addresses), count.index),
  ]
}

output "cassandra" {
  value = join(",", aws_instance.cassandra.*.public_ip)
}

