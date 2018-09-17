# @author: Alejandro Galue <agalue@opennms.org>

data "template_file" "opennms_ui" {
  count    = "${length(var.onms_ui_ip_addresses)}"
  template = "${file("${path.module}/templates/opennms.ui.tpl")}"

  vars {
    hostname               = "${element(keys(var.onms_ui_ip_addresses), count.index)}"
    domainname             = "${aws_route53_zone.private.name}"
    redis_server           = ""
    dependencies           = "${join(",",formatlist("%v:5432", aws_route53_record.postgresql_private.*.name))},${join(",",formatlist("%v:9042", aws_route53_record.cassandra_private.*.name))},${join(",",formatlist("%v:9200", aws_route53_record.elasticsearch_data_private.*.name))}"
    postgres_onms_url      = "jdbc:postgresql://${join(",", formatlist("%v:5432", aws_route53_record.postgresql_private.*.name))}/opennms?targetServerType=master&amp;loadBalanceHosts=false"
    postgres_server        = "${element(aws_route53_record.postgresql_private.*.name, 0)}"
    cassandra_seed         = "${element(aws_route53_record.cassandra_private.*.name, 0)}"
    elastic_url            = "http://${element(aws_route53_record.elasticsearch_data_private.*.name, 0)}:9200"
    elastic_user           = "elastic"
    elastic_password       = "${lookup(var.settings, "elastic_password")}"
    elastic_index_strategy = "${lookup(var.settings, "elastic_flow_index_strategy")}"
    webui_endpoint         = "${aws_elb.opennms_ui.dns_name}"
    use_30sec_frequency    = "${lookup(var.settings, "onms_use_30sec_frequency")}"
  }
}

resource "aws_instance" "opennms_ui" {
  count         = "${length(var.onms_ui_ip_addresses)}"
  ami           = "${data.aws_ami.opennms.image_id}"
  instance_type = "${lookup(var.instance_types, "onms_ui")}"
  subnet_id     = "${aws_subnet.public.id}"
  key_name      = "${var.aws_key_name}"
  private_ip    = "${element(values(var.onms_ui_ip_addresses), count.index)}"
  user_data     = "${element(data.template_file.opennms_ui.*.rendered, count.index)}"

  associate_public_ip_address = true

  vpc_security_group_ids = [
    "${aws_security_group.common.id}",
    "${aws_security_group.opennms_ui.id}",
  ]

  depends_on = [
    "aws_instance.opennms", # As it is the main OpenNMS the responsible for initialize the database and Cassandra.
    "aws_route53_record.opennms_ui_private",
  ]

  connection {
    user        = "ec2-user"
    private_key = "${file("${var.aws_private_key}")}"
  }

  timeouts {
    create = "30m"
    delete = "15m"
  }

  tags {
    Name = "Terraform OpenNMS UI Server ${count.index + 1}"
  }
}

resource "aws_route53_record" "opennms_ui" {
  count   = "${length(var.onms_ui_ip_addresses)}"
  zone_id = "${aws_route53_zone.main.zone_id}"
  name    = "${element(keys(var.onms_ui_ip_addresses), count.index)}.${aws_route53_zone.main.name}"
  type    = "A"
  ttl     = "${var.dns_ttl}"
  records = [
    "${element(aws_instance.opennms_ui.*.public_ip, count.index)}",
  ]
}

resource "aws_route53_record" "opennms_ui_private" {
  count   = "${length(var.onms_ui_ip_addresses)}"
  zone_id = "${aws_route53_zone.private.zone_id}"
  name    = "${element(keys(var.onms_ui_ip_addresses), count.index)}.${aws_route53_zone.private.name}"
  type    = "A"
  ttl     = "${var.dns_ttl}"
  records = [
    "${element(values(var.onms_ui_ip_addresses), count.index)}",
  ]
}
resource "aws_elb" "opennms_ui" {
  name            = "opennms"
  internal        = false
  subnets         = ["${aws_subnet.elb.id}"]
  security_groups = ["${aws_security_group.opennms_ui.id}"]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/opennms/login.jsp"
    interval            = 30
  }

  tags {
    Name = "Terraform OpenNMS UI ELB"
  }
}

resource "aws_elb_attachment" "opennms_ui" {
  count    = "${length(var.onms_ui_ip_addresses)}"
  elb      = "${aws_elb.opennms_ui.id}"
  instance = "${element(aws_instance.opennms_ui.*.id, count.index)}"
}

resource "aws_lb_cookie_stickiness_policy" "opennms_ui" {
  name                     = "opennms-ui-policy"
  load_balancer            = "${aws_elb.opennms_ui.id}"
  lb_port                  = 80
  cookie_expiration_period = 86400
}

resource "aws_route53_record" "opennms_ui_elb" {
  zone_id = "${data.aws_route53_zone.parent.zone_id}"
  name    = "onmsui.${aws_route53_zone.main.name}"
  type    = "A"

  alias {
    name                   = "${aws_elb.opennms_ui.dns_name}"
    zone_id                = "${aws_elb.opennms_ui.zone_id}"
    evaluate_target_health = true
  }
}

output "onmsui" {
  value = "${join(",",aws_instance.opennms_ui.*.public_ip)}"
}
