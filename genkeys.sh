#!/bin/bash
#
# Install the certbot to generate SSL
# certs easily from LetsEncrypt:
#
#     brew install certbot
#

ssh-keygen -f keys/bastion -q
ssh-keygen -f keys/private -q
