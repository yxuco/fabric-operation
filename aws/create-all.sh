#!/bin/bash
# create EKS cluster and setup EFS
# usage: create-all.sh env region profile
# e.g., create-all.sh fab us-west-2 prod
# specify profile if aws user assume a role of a different account, the assumed role should be defined in ~/.aws/config

cd "$( dirname "${BASH_SOURCE[0]}" )"

./create-key-pair.sh "$@"
# ./create-s3-bucket.sh "$@"
./create-cluster.sh "$@"
./deploy-efs.sh "$@"
./configure-bastion.sh "$@"
