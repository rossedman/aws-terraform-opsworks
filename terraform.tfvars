#
# App Specifics
# This will set naming conventions for everything in AWS
#
app_name = "BasicApp"
environment = "dev"
bastion_key = "keys/bastion.pub"
private_key = "keys/private.pub"

#
# Allowed To SSH
# this can be a comma-separated list of cidr blocks and ip addresses
#
allowed_to_ssh = "0.0.0.0/0"

#
# Region & Zones
# set location. make sure AZs are located in region provided
#
region = "us-west-2"
availability_zones = "us-west-2a,us-west-2b"

#
# CIDR Blocks
#
vpc_cidr = "10.128.0.0/16"
public_subnets = "10.128.10.0/24,10.128.20.0/24"
private_subnets = "10.128.11.0/24,10.128.21.0/24"

#
# DNS Settings
#
internal_domain = "rossedman.internal"
