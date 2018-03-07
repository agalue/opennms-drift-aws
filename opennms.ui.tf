# @author: Alejandro Galue <agalue@opennms.org>

data "template_file" "opennms_ui" {
    count    = "${length(var.onms_ui_ip_addresses)}"
    template = "${file("${path.module}/templates/opennms.ui.tpl")}"

    vars {
        hostname        = "${element(keys(var.onms_ui_ip_addresses), count.index)}"
        domainname      = "${var.dns_zone}"
        opennms_server  = "${element(keys(var.onms_ip_addresses),0)}"
        postgres_server = "${element(keys(var.pg_ip_addresses),0)}"
        nfs_server      = "${element(keys(var.onms_ip_addresses),0)}" # TODO Using the Core OpenNMS
        webui_endpoint  = "${aws_elb.opennms_ui.dns_name}"
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
        "${aws_security_group.opennms_ui.id}"
    ]

    depends_on = [
        "aws_instance.opennms",
        "aws_route53_record.opennms_ui"
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
    name    = "${element(keys(var.onms_ui_ip_addresses), count.index)}.${var.dns_zone}"
    type    = "A"
    ttl     = "300"
    records = ["${element(values(var.onms_ui_ip_addresses), count.index)}"]
}

resource "aws_elb" "opennms_ui" {
    name            = "opennms"
    internal        = false
    subnets         = ["${aws_subnet.public.id}"]
    security_groups = ["${aws_security_group.opennms_ui.id}"]

    listener {
        instance_port     = 8980
        instance_protocol = "http"
        lb_port           = 8980
        lb_protocol       = "http"
    }

    listener {
        instance_port     = 3000
        instance_protocol = "http"
        lb_port           = 3000
        lb_protocol       = "http"
    }

    health_check {
        healthy_threshold   = 2
        unhealthy_threshold = 2
        timeout             = 3
        target              = "HTTP:8980/opennms/login.jsp"
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

output "onmsui" {
    value = "${join(",",aws_instance.opennms_ui.*.public_ip)}"
}
