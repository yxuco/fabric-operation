#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

cd "$( dirname "${BASH_SOURCE[0]}" )"
source env.sh "$@"

region=$(aws configure get region)
echo "delete stack ${EKS_STACK} in region ${region}"
eksctl delete cluster --name ${EKS_STACK}
