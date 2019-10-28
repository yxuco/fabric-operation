#!/bin/bash

cd "$( dirname "${BASH_SOURCE[0]}" )"
source env.sh

echo "create EKS cluster ${EKS_STACK}"
echo "it may take 15 minutes ..."
starttime=$(date +%s)
eksctl create cluster --ssh-access --ssh-public-key ${KEYNAME} --name ${EKS_STACK} --region ${AWS_REGION} --node-type ${EKS_NODE_TYPE} --kubeconfig ${KUBECONFIG} --zones ${AWS_ZONES} --nodes ${EKS_NODE_COUNT}
echo "EKS cluster created in $(($(date +%s)-starttime)) seconds."

echo "verify nodes in EKS cluster ${EKS_STACK}"
kubectl get nodes
