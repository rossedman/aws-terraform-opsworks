/*--------------------------------------------------
 * Opsworks
 *
 * Establish a jumphost on the public subnet perimeter
 * also sets ssh key for transparent jumping
 *-------------------------------------------------*/
module "opsworks_stack" {
  source = "github.com/rossedman/aws-terraform-modules/devtools/opsworks/stack"
  cookbook_bucket = "${var.cookbook_bucket}"
  default_subnet_id = "${element(split(",",module.network.private_ids),0)}" # first private_subnet
  default_ssh_key_name = "${aws_key_pair.private.key_name}"
  region = "${var.region}"
  stack_name = "teststack"
  vpc_id = "${module.network.vpc_id}"
}

/*--------------------------------------------------
 * Opsworks Code / Application
 *-------------------------------------------------*/
resource "aws_opsworks_application" "php" {
  name = "php-app"
  short_name = "php-app"
  type = "other"
  stack_id = "${module.opsworks_stack.id}"
  app_source {
    type = "git"
    revision = "master"
    url = "https://github.com/rossedman/aws-opsworks-simple-app.git"
  }
}

/*--------------------------------------------------
 * Load Balancers
 *-------------------------------------------------*/
resource "aws_elb" "web" {
  count = 3
  cross_zone_load_balancing = true
  subnets = ["${split(",", module.network.public_ids)}"]
  security_groups = [
    "${module.network.vpc_sg}",
    "${module.elb_security_group.id}"
  ]

  listener {
    instance_port = 80
    instance_protocol = "http"
    lb_port = 80
    lb_protocol = "http"
  }

  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 2
    timeout = 3
    target = "HTTP:80/"
    interval = 5
  }

  tags {
    app = "${var.app_name}"
    env = "${var.environment}"
  }
}

/*--------------------------------------------------
 * Web Layers
 *-------------------------------------------------*/
resource "aws_opsworks_custom_layer" "web" {
  count = 3
  auto_healing = true
  stack_id = "${module.opsworks_stack.id}"
  name = "php-layer-${count.index}"
  short_name = "php-layer-${count.index}"
  auto_assign_public_ips = false
  custom_security_group_ids = ["${module.network.vpc_sg}"]
  elastic_load_balancer = "${element(aws_elb.web.*.name, count.index)}"
  drain_elb_on_shutdown = true
  custom_configure_recipes = ["php-app::configure"]
  custom_deploy_recipes = ["php-app::configure","php-app::deploy"]
}

resource "aws_opsworks_custom_layer" "elasticsearch" {
  auto_healing = true
  stack_id = "${module.opsworks_stack.id}"
  name = "elasticsearch"
  short_name = "elasticsearch"
  auto_assign_public_ips = false
  custom_security_group_ids = ["${module.network.vpc_sg}"]
}
