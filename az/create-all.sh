#!/bin/bash
# create all Azure cluster and storage components for a specified $ENV_NAME and $AZ_REGION
# usage: create-all.sh env region
# default value: ENV_NAME="fab", AZ_REGION="westus2"

cd "$( dirname "${BASH_SOURCE[0]}" )"

./create-cluster "$@"
./create-storage "$@"
./create-bastion "$@"