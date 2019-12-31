#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

# Execute this script on bastion host to expose gateway load-balancer ports to $MYCIDR
# usage: ./setup-service-sg.sh <org-name> <service-name> [<ports>]
# e.g., ./setup-service-sg.sh "netop1" "gateway"
# default ports="7081-7082"

ORG=${1}
SVC_NAME=${2}
PORTS=${3:-"7081-7082"}
ELB_HOST=""

function waitForService {
  ELB_HOST=$(kubectl get service ${SVC_NAME} -n ${ORG} -o=jsonpath='{.status.loadBalancer.ingress[0].hostname}')
  local cnt=1

  until [ ! -z "${ELB_HOST}" ] || [ ${cnt} -gt 5 ]; do
    sleep 5s
    echo -n "."
    ELB_HOST=$(kubectl get service ${SVC_NAME} -n ${ORG} -o=jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    cnt=$((${cnt}+1))
  done
}

# check if elb for the service exists
waitForService
if [ -z "${ELB_HOST}" ]; then
  echo "cannot find k8s ${SVC_NAME} service for org: ${ORG}"
  exit 1
fi
echo "${SVC_NAME} service load-balancer host: ${ELB_HOST}"

# set security rule for gateway service
elbSgid=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=k8s-elb-*" "Name=description,Values=*(${ORG}/${SVC_NAME})" --query 'SecurityGroups[*].GroupId' --output text)
if [ -z "${elbSgid}" ]; then
  echo "cannot find ${SVC_NAME} service group for org: ${ORG}"
  exit 1
fi
echo "open ${SVC_NAME} load balancer port ${PORTS} to ${MYCIDR}"
aws ec2 authorize-security-group-ingress --group-id ${elbSgid} --protocol tcp --port ${PORTS} --cidr ${MYCIDR}

if [ "${SVC_NAME}" == "gateway" ]; then
  echo "browse gateway swagger UI at http://${ELB_HOST}:7081/swagger"
else
  echo "access ${SVC_NAME} service at http://${ELB_HOST}:${PORTS}"
fi
