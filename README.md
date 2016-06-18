

## Setup

1. Register cert with AWS Certificate Manager (and get ARN)
2. Generate bastion/instance keys by running `./genkeys.sh`
3. Create a bucket for cookbooks & releases to live in
4. Upload cookbooks to that bucket
5. Fill out variables in `terraform.tfvars`
6. Run Terraform
7. Create instances in stacks
8. Point domain from SSL to ELB
