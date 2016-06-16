provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region = "${var.region}"
}

/*--------------------------------------------------
 * Network
 *
 * This sets up VPC, Subnets, Internet Gateway,
 * Routing Tables, and more.
 *-------------------------------------------------*/
module "network" {
  source = "github.com/rossedman/aws-terraform-modules/network"
  azs = "${var.availability_zones}"
  cidr = "${var.vpc_cidr}"
  public_subnets = "${var.public_subnets}"
  private_subnets = "${var.private_subnets}"
  internal_domain = "${var.internal_domain}"
  app_name = "${var.app_name}"
  environment = "${var.environment}"
}

/*--------------------------------------------------
 * Bastion
 *
 * Establish a jumphost on the public subnet perimeter
 * also sets ssh key for transparent jumping
 *-------------------------------------------------*/
module "bastion" {
  source = "github.com/rossedman/aws-terraform-modules/compute/bastion"
  allowed_to_ssh = "${var.allowed_to_ssh}"
  ami = "${lookup(var.aws_linux_amis_ebs, var.region)}"
  public_key = "${var.bastion_key}"
  security_group_ids = "${module.network.vpc_sg}"
  subnet_id = "${element(split(",", module.network.public_ids), 0)}"
  vpc_id = "${module.network.vpc_id}"
  vpc_cidr = "${module.network.vpc_cidr}"
  app_name = "${var.app_name}"
  environment = "${var.environment}"
}

/*--------------------------------------------------
 * Private Key
 *
 * Create key for private instance access
 *-------------------------------------------------*/
resource "aws_key_pair" "private" {
  key_name = "private-key"
  public_key = "${file(var.private_key)}"
}

/*--------------------------------------------------
 * Web Security
 *
 * set security groups for public access to ELB and then
 * ELB access-only to instances behind the load balancer
 *-------------------------------------------------*/
module "elb_security_group" {
  source = "github.com/rossedman/aws-terraform-modules/network/security/sg_http"
  name = "elb-http"
  vpc_id = "${module.network.vpc_id}"
  app_name = "${var.app_name}"
  environment = "${var.environment}"
}

module "private_web_security_group" {
  source = "github.com/rossedman/aws-terraform-modules/network/security/sg_http"
  name = "opsworks-http"
  vpc_id = "${module.network.vpc_id}"
  #incoming_cidr = "${module.elb_security_group.id}"
  app_name = "${var.app_name}"
  environment = "${var.environment}"
}

/*--------------------------------------------------
 * Load Balancer
 *-------------------------------------------------*/
resource "aws_elb" "web" {
  cross_zone_load_balancing = true
  subnets = ["${split(",", module.network.public_ids)}"]
  security_groups = ["${module.elb_security_group.id}"]

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
    interval = 60
  }

  tags {
    app = "${var.app_name}"
    env = "${var.environment}"
  }
}
