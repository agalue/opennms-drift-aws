# @author: Alejandro Galue <agalue@opennms.org>

data "template_file" "zookeeper" {
  count    = length(var.zookeeper_ip_addresses)
  template = file("${path.module}/templates/zookeeper.tpl")

  vars = {
    node_id       = count.index + 1
    vpc_cidr      = var.vpc_cidr
    hostname      = element(keys(var.zookeeper_ip_addresses), count.index)
    domainname    = aws_route53_zone.private.name
    total_servers = length(var.zookeeper_ip_addresses)
  }
}

resource "aws_instance" "zookeeper" {
  count         = length(var.zookeeper_ip_addresses)
  ami           = data.aws_ami.kafka.image_id
  instance_type = var.instance_types["zookeeper"]
  subnet_id     = aws_subnet.public.id
  key_name      = var.aws_key_name
  private_ip    = element(values(var.zookeeper_ip_addresses), count.index)
  user_data     = element(data.template_file.zookeeper.*.rendered, count.index)

  associate_public_ip_address = true

  vpc_security_group_ids = [
    aws_security_group.common.id,
    aws_security_group.zookeeper.id,
  ]

  depends_on = [aws_route53_record.zookeeper_private]

  root_block_device {
    volume_type = "gp2"
    volume_size = var.disk_space["zookeeper"]
  }

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
    Name        = "Terraform Zookeeper Server ${count.index + 1}"
    Environment = "Test"
    Department  = "Support"
  }
}

resource "aws_route53_record" "zookeeper" {
  count   = length(var.zookeeper_ip_addresses)
  zone_id = aws_route53_zone.main.zone_id
  name    = "${element(keys(var.zookeeper_ip_addresses), count.index)}.${aws_route53_zone.main.name}"
  type    = "A"
  ttl     = var.dns_ttl
  records = [
    element(aws_instance.zookeeper.*.public_ip, count.index),
  ]
}

resource "aws_route53_record" "zookeeper_private" {
  count   = length(var.zookeeper_ip_addresses)
  zone_id = aws_route53_zone.private.zone_id
  name    = "${element(keys(var.zookeeper_ip_addresses), count.index)}.${aws_route53_zone.private.name}"
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
    element(values(var.zookeeper_ip_addresses), count.index),
  ]
}

output "zookeeper" {
  value = join(",", aws_instance.zookeeper.*.public_ip)
}

