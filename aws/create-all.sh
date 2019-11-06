#!/bin/bash
# create EKS cluster and setup EFS
# usage: create-all.sh env region profile
# e.g., create-all.sh dev us-west-2
# specify profile if aws user assume a role of a different account, the assumed role should be defined in ~/.aws/config

cd "$( dirname "${BASH_SOURCE[0]}" )"

# create key pair for managing EFS
./create-key-pair.sh "$@"

# create s3 buckets for sharing files
./create-s3-bucket.sh "$@"

# create EKS cluster and setup EKS nodes
./create-cluster.sh "$@"

# create EFS volume and bastion host for EFS client
./deploy-efs.sh "$@"

# set rules for security groups, so it won't open to the world
./bastion-sg-rule.sh "$@"

# initilaize bastion host
./setup-bastion.sh "$@"
