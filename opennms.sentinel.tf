# @author: Alejandro Galue <agalue@opennms.org>

data "template_file" "opennms_sentinel" {
  count    = length(var.onms_sentinel_ip_addresses)
  template = file("${path.module}/templates/opennms.sentinel.tpl")

  vars = {
    hostname     = element(keys(var.onms_sentinel_ip_addresses), count.index)
    domainname   = aws_route53_zone.private.name
    dependencies = "${aws_route53_record.opennms_private[0].name}:8980" # To make sure that the DB was initialized, and the rest of the dependencies are available
    postgres_onms_url = "jdbc:postgresql://${join(
      ",",
      formatlist("%v:5432", aws_route53_record.postgresql_private.*.name),
    )}/opennms?targetServerType=master&amp;loadBalanceHosts=false"
    kafka_servers           = "${element(aws_route53_record.kafka_private.*.name, 0)}:9092"
    kafka_security_protocol = var.settings["kafka_security_protocol"]
    kafka_security_module   = var.settings["kafka_security_module"]
    kafka_client_mechanism  = var.settings["kafka_client_mechanism"]
    kafka_user_name         = var.settings["kafka_user_name"]
    kafka_user_password     = var.settings["kafka_user_password"]
    kafka_max_message_size  = var.settings["kafka_max_message_size"]
    cassandra_servers       = element(aws_route53_record.cassandra_private.*.name, 0)
    elastic_url = join(
      ",",
      formatlist(
        "http://%v:9200",
        aws_route53_record.elasticsearch_data_private.*.name,
      ),
    )
    elastic_user           = var.settings["elastic_user"]
    elastic_password       = var.settings["elastic_password"]
    elastic_index_strategy = var.settings["elastic_flow_index_strategy"]
    opennms_url            = "http://${aws_route53_record.opennms_private[0].name}:8980/opennms"
    sentinel_location      = "AWS"
  }
}

resource "aws_instance" "opennms_sentinel" {
  count         = length(var.onms_sentinel_ip_addresses)
  ami           = data.aws_ami.sentinel.image_id
  instance_type = var.instance_types["onms_sentinel"]
  subnet_id     = aws_subnet.public.id
  key_name      = var.aws_key_name
  private_ip    = element(values(var.onms_sentinel_ip_addresses), count.index)
  user_data     = element(data.template_file.opennms_sentinel.*.rendered, count.index)

  associate_public_ip_address = true

  vpc_security_group_ids = [
    aws_security_group.common.id,
    aws_security_group.sentinel.id,
  ]

  depends_on = [aws_route53_record.opennms_sentinel_private]

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
    Name        = "Terraform OpenNMS Sentinel ${count.index + 1}"
    Environment = "Test"
    Department  = "Support"
  }
}

resource "aws_route53_record" "opennms_sentinel" {
  count   = length(var.onms_sentinel_ip_addresses)
  zone_id = aws_route53_zone.main.zone_id
  name    = "${element(keys(var.onms_sentinel_ip_addresses), count.index)}.${aws_route53_zone.main.name}"
  type    = "A"
  ttl     = var.dns_ttl
  records = [
    element(aws_instance.opennms_sentinel.*.public_ip, count.index),
  ]
}

resource "aws_route53_record" "opennms_sentinel_private" {
  count   = length(var.onms_sentinel_ip_addresses)
  zone_id = aws_route53_zone.private.zone_id
  name    = "${element(keys(var.onms_sentinel_ip_addresses), count.index)}.${aws_route53_zone.private.name}"
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
    element(values(var.onms_sentinel_ip_addresses), count.index),
  ]
}

output "sentinel" {
  value = join(",", aws_instance.opennms_sentinel.*.public_ip)
}

