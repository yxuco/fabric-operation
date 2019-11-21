#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

cd "$( dirname "${BASH_SOURCE[0]}" )"
source env.sh "$@"

echo "create EKS cluster ${EKS_STACK}"
echo "it may take 15 minutes ..."
starttime=$(date +%s)
eksctl create cluster --ssh-access --ssh-public-key ${KEYNAME} --name ${EKS_STACK} --region ${AWS_REGION} --node-type ${EKS_NODE_TYPE} --kubeconfig ${KUBECONFIG} --zones ${AWS_ZONES} --nodes ${EKS_NODE_COUNT}
echo "EKS cluster created in $(($(date +%s)-starttime)) seconds."

hash kubectl
if [ "$?" -eq 0 ]; then
  echo "verify nodes in EKS cluster ${EKS_CLUSTER}"
  kubectl get nodes
fi
