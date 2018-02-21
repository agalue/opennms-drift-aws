# @author: Alejandro Galue <agalue@opennms.org>

data "template_file" "elasticsearch_master" {
    count    = "${length(var.es_master_ip_addresses)}"
    template = "${file("${path.module}/templates/elasticsearch.tpl")}"

    vars {
        node_id         = "${count.index + 1}"
        vpc_cidr        = "${var.vpc_cidr}"
        hostname        = "${element(keys(var.es_master_ip_addresses), count.index)}"
        domainname      = "${var.dns_zone}"
        es_version      = "${lookup(var.versions, "elasticsearch")}"
        es_cluster_name = "${lookup(var.settings, "cluster_name")}"
        es_seed_name    = "${join(",",keys(var.es_master_ip_addresses))}"
        es_password     = "${lookup(var.settings, "elastic_password")}"
        es_is_master    = "true"
    }
}

resource "aws_instance" "elasticsearch_master" {
    count         = "${length(var.es_master_ip_addresses)}"
    ami           = "${lookup(var.aws_amis, var.aws_region)}"
    instance_type = "${lookup(var.instance_types, "es_master")}"
    subnet_id     = "${aws_subnet.public.id}"
    key_name      = "${var.aws_key_name}"
    private_ip    = "${element(values(var.es_master_ip_addresses), count.index)}"
    user_data     = "${element(data.template_file.elasticsearch_master.*.rendered, count.index)}"

    associate_public_ip_address = true

    vpc_security_group_ids = [
        "${aws_security_group.common.id}",
        "${aws_security_group.elasticsearch.id}"
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
        Name = "Terraform Elasticsearch Master Server ${count.index + 1}"
    }
}

resource "aws_route53_record" "elasticsearch_master" {
    count   = "${length(var.es_master_ip_addresses)}"
    zone_id = "${aws_route53_zone.main.zone_id}"
    name    = "${element(keys(var.es_master_ip_addresses), count.index)}.${var.dns_zone}"
    type    = "A"
    ttl     = "300"
    records = ["${element(values(var.es_master_ip_addresses), count.index)}"]
}

output "esmaster" {
    value = "${join(",",aws_instance.elasticsearch_master.*.public_ip)}"
}
