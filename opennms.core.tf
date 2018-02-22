# @author: Alejandro Galue <agalue@opennms.org>

data "template_file" "opennms" {
    template = "${file("${path.module}/templates/opennms.core.tpl")}"

    vars {
        vpc_cidr            = "${var.vpc_cidr}"
        hostname            = "${element(keys(var.onms_ip_addresses),0)}"
        domainname          = "${var.dns_zone}"
        onms_repo           = "${lookup(var.versions, "onms_repo")}"
        onms_version        = "${lookup(var.versions, "onms_version")}"
        postgres_server     = "${element(keys(var.pg_ip_addresses),0)}"
        activemq_url        = "failover:(${join(",",formatlist("tcp://%v:61616", keys(var.amq_ip_addresses)))})?randomize=false"
        elastic_url         = "${join(",",formatlist("http://%v:9200", keys(var.es_data_ip_addresses)))}"
        elastic_user        = "elastic"
        elastic_password    = "${lookup(var.settings, "elastic_password")}"
        kafka_servers       = "${join(",",formatlist("%v:9092", keys(var.kafka_ip_addresses)))}"
        cassandra_servers   = "${join(",", keys(var.cassandra_ip_addresses))}"
        cassandra_repfactor = "${lookup(var.settings, "cassandra_replication_factor")}"
    }
}

resource "aws_instance" "opennms" {
    ami           = "${lookup(var.aws_amis, var.aws_region)}"
    instance_type = "${lookup(var.instance_types, "onms_core")}"
    subnet_id     = "${aws_subnet.public.id}"
    key_name      = "${var.aws_key_name}"
    private_ip    = "${element(values(var.onms_ip_addresses),0)}"
    user_data     = "${data.template_file.opennms.rendered}"

    associate_public_ip_address = true

    vpc_security_group_ids = [
        "${aws_security_group.common.id}",
        "${aws_security_group.opennms.id}"
    ]

    depends_on = [
        "aws_instance.postgresql",
        "aws_instance.activemq",
        "aws_instance.kafka",
        "aws_instance.elasticsearch_data"
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
        Name = "Terraform OpenNMS Core Server"
    }
}

resource "aws_route53_record" "opennms" {
    zone_id = "${aws_route53_zone.main.zone_id}"
    name    = "${element(keys(var.onms_ip_addresses),0)}.${var.dns_zone}"
    type    = "A"
    ttl     = "300"
    records = ["${element(values(var.onms_ip_addresses),0)}"]
}

output "opennms" {
    value = "${aws_instance.opennms.public_ip}"
}
