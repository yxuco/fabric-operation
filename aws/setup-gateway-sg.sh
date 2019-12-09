#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

# Execute this script on bastion host to expose gateway load-balancer ports to $MYCIDR
# usage: ./setup-gateway-sg.sh <org-name>

ORG=${1:-"netop1"}

function waitForService {
  local svc=$(kubectl get service gateway -n ${ORG} -o=jsonpath='{.spec.type}')
  local cnt=1

  until [ "${svc}" == "LoadBalancer" ] || [ ${cnt} -ge 5 ]; do
    sleep 5s
    echo -n "."
    svc=$(kubectl get service gateway -n ${ORG} -o=jsonpath='{.spec.type}')
    cnt=$((${cnt}+1))
  done
}

# check if elb for gateway service exists
waitForService
elbHost=$(kubectl get service gateway -n ${ORG} -o=jsonpath='{.status.loadBalancer.ingress[0].hostname}')
if [ -z "${elbHost}" ]; then
  echo "cannot find k8s gateway service for org: ${ORG}"
  exit 1
fi
echo "gateway service load-balancer host: ${elbHost}"

# set security rule for gateway service
elbSgid=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=k8s-elb-*" "Name=description,Values=*(${ORG}/gateway)" --query 'SecurityGroups[*].GroupId' --output text)
if [ -z "${elbSgid}" ]; then
  echo "cannot find gateway service group for org: ${ORG}"
  exit 1
fi
echo "open gateway load balancer port 7081-7082 to ${MYCIDR}"
aws ec2 authorize-security-group-ingress --group-id ${elbSgid} --protocol tcp --port 7081-7082 --cidr ${MYCIDR}

echo "browse gateway swagger UI at http://${elbHost}:7081/swagger"
