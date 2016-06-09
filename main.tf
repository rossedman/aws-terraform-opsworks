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
  source = "modules/network"

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
  source = "modules/network/bastion"

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
 * Opsworks
 *
 * Establish a jumphost on the public subnet perimeter
 * also sets ssh key for transparent jumping
 *-------------------------------------------------*/

 #
 # Opsworks Role
 #
 # give opsworks the ability to work with ec2 instances as
 # well as s3 and opsworks.
 #
 resource "aws_iam_role" "opsworks" {
   name = "opsworks_role"
   assume_role_policy = "${file("policies/opsworks-role.json")}"
 }

 resource "aws_iam_role_policy" "opsworks" {
   name = "opsworks_role_policy"
   role = "${aws_iam_role.opsworks.id}"
   policy = "${file("policies/opsworks-policy.json")}"
 }

 #
 # Opsworks Instance Role
 #
 # create role and attach policy. this will be provided
 # to new instances in the stack.
 #
 resource "aws_iam_role" "opsworks_instances" {
   name = "opsworks_instance_role"
   assume_role_policy = "${file("policies/opsworks-instance-role.json")}"
 }

 resource "aws_iam_role_policy" "opsworks_instances" {
   name = "opsworks_instance_policy"
   role = "${aws_iam_role.opsworks_instances.id}"
   policy = "${file("policies/opsworks-instance-policy.json")}"
 }

 resource "aws_iam_instance_profile" "opsworks" {
   name = "opsworks_instances"
   roles = ["${aws_iam_role.opsworks_instances.name}"]
 }

 #
 # Opsworks Stack
 #
 resource "aws_opsworks_stack" "main" {
   name = "${var.app_name}-stack"
   region = "${var.region}"
   default_os = "Amazon Linux 2016.03"
   agent_version = "LATEST"
   service_role_arn = "${aws_iam_role.opsworks.arn}"
   default_instance_profile_arn = "${aws_iam_instance_profile.opsworks.arn}"
   configuration_manager_version = "12"
   vpc_id = "${module.network.vpc_id}"
   default_subnet_id = "${element(split(",",module.network.private_ids),0)}"
   default_ssh_key_name = "${aws_key_pair.private.key_name}"
   use_opsworks_security_groups = false
   use_custom_cookbooks = true

   custom_cookbooks_source {
     type = "s3"
     url = "https://s3-us-west-2.amazonaws.com/testapp.storage/cookbooks/cookbooks.tar.gz"
   }
 }

 resource "aws_opsworks_application" "php" {
   name = "lms"
   short_name = "lms"
   type = "other"
   stack_id = "${aws_opsworks_stack.main.id}"
   app_source {
     type = "git"
     revision = "version1"
     url = "https://github.com/awslabs/opsworks-demo-php-simple-app.git"
   }
 }

 /*--------------------------------------------------
  * Web Security
  *-------------------------------------------------*/
 resource "aws_security_group" "web" {
   name = "http"
   description = "Security group for ELB"
   vpc_id = "${module.network.vpc_id}"

   ingress {
     from_port = 80
     to_port = 80
     protocol = "tcp"
     cidr_blocks = ["0.0.0.0/0"]
   }

   egress {
     from_port = 0
     to_port = 0
     protocol = "-1"
     cidr_blocks = ["0.0.0.0/0"]
   }

   tags {
     app = "${var.app_name}"
     env = "${var.environment}"
   }
 }

/*--------------------------------------------------
 * Load Balancer
 *-------------------------------------------------*/
resource "aws_elb" "web" {
  cross_zone_load_balancing = true
  subnets = ["${split(",", module.network.public_ids)}"]
  security_groups = [
    "${module.network.vpc_sg}",
    "${aws_security_group.web.id}"
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
    interval = 60
  }

  tags {
    app = "${var.app_name}"
    env = "${var.environment}"
  }
}

/*--------------------------------------------------
 * PHP Layer
 *-------------------------------------------------*/
 /*resource "aws_opsworks_php_app_layer" "app" {
   stack_id = "${aws_opsworks_stack.main.id}"
   name = "php-app-test"
   auto_assign_public_ips = false
   custom_security_group_ids = ["${module.network.vpc_sg}"]
   elastic_load_balancer = "${aws_elb.web.name}"
 }*/

 resource "aws_opsworks_custom_layer" "app" {
    auto_healing = true
    stack_id = "${aws_opsworks_stack.main.id}"
    name = "PHP App Test"
    short_name = "php_app_test"
    auto_assign_public_ips = false
    custom_security_group_ids = ["${module.network.vpc_sg}"]
    elastic_load_balancer = "${aws_elb.web.name}"
    drain_elb_on_shutdown = true
 }

 resource "aws_opsworks_instance" "php" {
   depends_on = [
     "aws_iam_role.opsworks",
     "aws_iam_role_policy.opsworks",
     "aws_iam_instance_profile.opsworks",
     "aws_iam_role.opsworks_instances",
     "aws_iam_role_policy.opsworks_instances"
   ]
   count = 4
   stack_id = "${aws_opsworks_stack.main.id}"
   layer_ids = ["${aws_opsworks_custom_layer.app.id}"]
   auto_scaling_type = "load"
   install_updates_on_boot = true
   instance_type = "t2.micro"
   state = "running"
   root_device_type = "ebs"
 }
