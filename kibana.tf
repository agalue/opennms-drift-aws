# @author: Alejandro Galue <agalue@opennms.org>

data "template_file" "kibana" {
    template = "${file("${path.module}/templates/kibana.tpl")}"

    vars {
        vpc_cidr   = "${var.vpc_cidr}"
        hostname   = "${element(keys(var.kibana_ip_addresses),0)}"
        domainname = "${var.dns_zone}"
        es_version = "${lookup(var.versions, "kibana")}"
        es_url     = "http://${aws_elb.elasticsearch.dns_name}:9200"
    }
}

resource "aws_instance" "kibana" {
    ami           = "${lookup(var.aws_amis, var.aws_region)}"
    instance_type = "${lookup(var.instance_types, "kibana")}"
    subnet_id     = "${aws_subnet.public.id}"
    key_name      = "${var.aws_key_name}"
    private_ip    = "${element(values(var.kibana_ip_addresses),0)}"
    user_data     = "${data.template_file.kibana.rendered}"

    associate_public_ip_address = true

    vpc_security_group_ids = [
        "${aws_security_group.common.id}",
        "${aws_security_group.kibana.id}"
    ]

    depends_on = [
        "aws_instance.elasticsearch"
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
        Name = "Terraform Kibana Server"
    }
}

resource "aws_route53_record" "kibana" {
    zone_id = "${aws_route53_zone.main.zone_id}"
    name    = "${element(keys(var.kibana_ip_addresses),0)}.${var.dns_zone}"
    type    = "A"
    ttl     = "300"
    records = ["${element(values(var.kibana_ip_addresses),0)}"]
}

output "kibana" {
    value = "${aws_instance.kibana.public_ip}"
}
