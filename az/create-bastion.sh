#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

# create VM as a bastion host for a specified $ENV_NAME and $AZ_REGION
# usage: create-bastion.sh env region
# default value: ENV_NAME="fab", AZ_REGION="westus2"

cd "$( dirname "${BASH_SOURCE[0]}" )"
source env.sh "$@"

echo "create bastion host ${BASTION_HOST}"
starttime=$(date +%s)

# create bastion host if it does not exist already
check=$(az vm show -n ${BASTION_HOST} -g ${RESOURCE_GROUP} --query "provisioningState" -o tsv)
if [ "${check}" == "Succeeded" ]; then
  echo "bastion host ${BASTION_HOST} is already provisioned"
else
  echo "create bastion host ${BASTION_HOST} with admin-user ${BASTION_USER} ..."
  az vm create -n ${BASTION_HOST} -g ${RESOURCE_GROUP} --image UbuntuLTS --generate-ssh-keys --admin-username ${BASTION_USER}
fi

# update security rule for ssh from localhost
myip=$(curl ifconfig.me)
echo "set security rule to allow ssh from host ${myip}"
az network nsg rule update -g ${RESOURCE_GROUP} --nsg-name ${BASTION_HOST}NSG --name default-allow-ssh --source-address-prefixes ${myip}

echo "collect public IP of bastion host ${BASTION_HOST} ..."
pubip=$(az vm list-ip-addresses -n ${BASTION_HOST} -g ${RESOURCE_GROUP} --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" -o tsv)
sed -i -e "s/^export BASTION_IP=.*/export BASTION_IP=${pubip}/" ./env.sh

# setup bastion host
scp -q -o "StrictHostKeyChecking no" ./config/config-${ENV_NAME}.yaml ${BASTION_USER}@${pubip}:config.yaml
scp -q -o "StrictHostKeyChecking no" ./config/env.sh ${BASTION_USER}@${pubip}:env.sh
scp -q -o "StrictHostKeyChecking no" ./setup-bastion.sh ${BASTION_USER}@${pubip}:setup.sh

if [ "${check}" == "Succeeded" ]; then
  echo "skip setup for existing bastion host"
else
ssh -o "StrictHostKeyChecking no" ${BASTION_USER}@${pubip} << EOF
  ./setup.sh
EOF
fi

echo "Bastion host ${BASTION_HOST} created in $(($(date +%s)-starttime)) seconds."
echo "Access the bastion host by ssh:"
echo "  ssh ${BASTION_USER}@${pubip}"
