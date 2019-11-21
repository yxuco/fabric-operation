#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

# create compute engine instance as a bastion host for a specified $ENV_NAME and $GCP_ZONE
# usage: create-bastion.sh env zone
# example value: ENV_NAME="fab", GCP_ZONE="us-west1-c"

cd "$( dirname "${BASH_SOURCE[0]}" )"
source env.sh "$@"

echo "create bastion host ${BASTION_HOST}"
starttime=$(date +%s)

# create bastion host if it does not exist already
check=$(gcloud compute instances describe ${BASTION_HOST} --format="csv[no-heading](status)")
if [ "${check}" == "RUNNING" ]; then
  echo "bastion host ${BASTION_HOST} is already running"
else
  echo "create bastion host ${BASTION_HOST} with admin-user ${BASTION_USER} ..."
  gcloud compute instances create ${BASTION_HOST}
fi

# setup bastion host
gcloud compute scp --quiet --ssh-key-file ./config/${SSH_KEY} ./config/env.sh ${BASTION_USER}@${BASTION_HOST}:env.sh
gcloud compute scp --quiet --ssh-key-file ./config/${SSH_KEY} ./setup-bastion.sh ${BASTION_USER}@${BASTION_HOST}:setup.sh
gcloud compute ssh --quiet --ssh-key-file ./config/${SSH_KEY} ${BASTION_USER}@${BASTION_HOST} << EOF
  ./setup.sh
EOF

echo "Bastion host ${BASTION_HOST} created in $(($(date +%s)-starttime)) seconds."
echo "Access the bastion host by ssh:"
echo "  gcloud compute ssh --ssh-key-file ./config/${SSH_KEY} ${BASTION_USER}@${BASTION_HOST}"
