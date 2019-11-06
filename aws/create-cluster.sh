#!/bin/bash

cd "$( dirname "${BASH_SOURCE[0]}" )"
source env.sh "$@"

sed -i -e "s/^export ENV_NAME=.*/export ENV_NAME=${ENV_NAME}/" ./setup/env.sh
sed -i -e "s/^export EKS_STACK=.*/export EKS_STACK=${EKS_STACK}/g" ./setup/env.sh
if [[ ! -z "${AWS_PROFILE}" ]]; then
  sed -i -e "s/^export AWS_PROFILE=.*/export AWS_PROFILE=${AWS_PROFILE}/" ./setup/env.sh
else
  sed -i -e "s/^export AWS_PROFILE=.*/export AWS_PROFILE=/" ./setup/env.sh
fi

echo "create EKS cluster ${EKS_STACK}"
echo "it may take 15 minutes ..."
starttime=$(date +%s)
eksctl create cluster --ssh-access --ssh-public-key ${KEYNAME} --name ${EKS_STACK} --region ${AWS_REGION} --node-type ${EKS_NODE_TYPE} --kubeconfig ${KUBECONFIG} --zones ${AWS_ZONES} --nodes ${EKS_NODE_COUNT}
echo "EKS cluster created in $(($(date +%s)-starttime)) seconds."

echo "verify nodes in EKS cluster ${EKS_STACK}"
kubectl get nodes
