#!/bin/bash

cd "$( dirname "${BASH_SOURCE[0]}" )"
source env.sh

region=$(aws configure get region)
echo "delete stack ${EKS_STACK} in region ${region}"
eksctl delete cluster --name ${EKS_STACK}
