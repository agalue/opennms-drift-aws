# @author: Alejandro Galue <agalue@opennms.org>

data "template_file" "opennms_ui" {
  count    = length(var.onms_ui_ip_addresses)
  template = file("${path.module}/templates/opennms.ui.tpl")

  vars = {
    hostname          = element(keys(var.onms_ui_ip_addresses), count.index)
    domainname        = aws_route53_zone.private.name
    domainname_public = aws_route53_zone.main.name
    redis_server      = ""
    dependencies      = "${aws_route53_record.opennms_private[0].name}:8980" # To make sure that the DB was initialized, and the rest of the dependencies are available
    postgres_onms_url = "jdbc:postgresql://${join(
      ",",
      formatlist("%v:5432", aws_route53_record.postgresql_private.*.name),
    )}/opennms?targetServerType=master&amp;loadBalanceHosts=false"
    postgres_server = element(aws_route53_record.postgresql_private.*.name, 0)
    cassandra_seed  = element(aws_route53_record.cassandra_private.*.name, 0)
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
    use_30sec_frequency    = var.settings["onms_use_30sec_frequency"]
  }
}

resource "aws_instance" "opennms_ui" {
  count         = length(var.onms_ui_ip_addresses)
  ami           = data.aws_ami.opennms.image_id
  instance_type = var.instance_types["onms_ui"]
  subnet_id     = aws_subnet.public.id
  key_name      = var.aws_key_name
  private_ip    = element(values(var.onms_ui_ip_addresses), count.index)
  user_data     = element(data.template_file.opennms_ui.*.rendered, count.index)

  associate_public_ip_address = true

  vpc_security_group_ids = [
    aws_security_group.common.id,
    aws_security_group.opennms_ui.id,
  ]

  depends_on = [
    aws_instance.opennms,
    aws_route53_record.opennms_ui_private,
  ]

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
    Name        = "Terraform OpenNMS UI Server ${count.index + 1}"
    Environment = "Test"
    Department  = "Support"
  }
}

resource "aws_route53_record" "opennms_ui" {
  count   = length(var.onms_ui_ip_addresses)
  zone_id = aws_route53_zone.main.zone_id
  name    = "${element(keys(var.onms_ui_ip_addresses), count.index)}.${aws_route53_zone.main.name}"
  type    = "A"
  ttl     = var.dns_ttl
  records = [
    element(aws_instance.opennms_ui.*.public_ip, count.index),
  ]
}

resource "aws_route53_record" "opennms_ui_private" {
  count   = length(var.onms_ui_ip_addresses)
  zone_id = aws_route53_zone.private.zone_id
  name    = "${element(keys(var.onms_ui_ip_addresses), count.index)}.${aws_route53_zone.private.name}"
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
    element(values(var.onms_ui_ip_addresses), count.index),
  ]
}

output "onmsui" {
  value = join(",", aws_instance.opennms_ui.*.public_ip)
}

