# @author: Alejandro Galue <agalue@opennms.org>

data "template_file" "kafka" {
  count    = length(var.kafka_ip_addresses)
  template = file("${path.module}/templates/kafka.tpl")

  vars = {
    node_id    = count.index + 1
    hostname   = element(keys(var.kafka_ip_addresses), count.index)
    domainname = aws_route53_zone.private.name
    dependencies = join(
      ",",
      formatlist("%v:2181", aws_route53_record.zookeeper_private.*.name),
    )
    zookeeper_connect = "${join(
      ",",
      formatlist("%v:2181", aws_route53_record.zookeeper_private.*.name),
    )}/kafka"
    num_partitions      = var.settings["kafka_num_partitions"]
    replication_factor  = var.settings["kafka_replication_factor"]
    min_insync_replicas = var.settings["kafka_min_insync_replicas"]
    security_protocol   = var.settings["kafka_security_protocol"]
    security_mechanisms = var.settings["kafka_security_mechanisms"]
    admin_password      = var.settings["kafka_admin_password"]
    user_name           = var.settings["kafka_user_name"]
    user_password       = var.settings["kafka_user_password"]
    max_message_size    = var.settings["kafka_max_message_size"]
  }
}

resource "aws_instance" "kafka" {
  count         = length(var.kafka_ip_addresses)
  ami           = data.aws_ami.kafka.image_id
  instance_type = var.instance_types["kafka"]
  subnet_id     = aws_subnet.public.id
  key_name      = var.aws_key_name
  private_ip    = element(values(var.kafka_ip_addresses), count.index)
  user_data     = element(data.template_file.kafka.*.rendered, count.index)

  associate_public_ip_address = true

  vpc_security_group_ids = [
    aws_security_group.common.id,
    aws_security_group.kafka.id,
  ]

  depends_on = [aws_route53_record.kafka_private]

  root_block_device {
    volume_type = "gp2"
    volume_size = var.disk_space["kafka"]
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
    Name        = "Terraform Kafka Server ${count.index + 1}"
    Environment = "Test"
    Department  = "Support"
  }
}

resource "aws_route53_record" "kafka" {
  count   = length(var.kafka_ip_addresses)
  zone_id = aws_route53_zone.main.zone_id
  name    = "${element(keys(var.kafka_ip_addresses), count.index)}.${aws_route53_zone.main.name}"
  type    = "A"
  ttl     = var.dns_ttl
  records = [
    element(aws_instance.kafka.*.public_ip, count.index),
  ]
}

resource "aws_route53_record" "kafka_private" {
  count   = length(var.kafka_ip_addresses)
  zone_id = aws_route53_zone.private.zone_id
  name    = "${element(keys(var.kafka_ip_addresses), count.index)}.${aws_route53_zone.private.name}"
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
    element(values(var.kafka_ip_addresses), count.index),
  ]
}

output "kafka" {
  value = join(",", aws_instance.kafka.*.public_ip)
}

