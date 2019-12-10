#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

# create Google Cloud Filestore for a specified $ENV_NAME and $GCP_ZONE
# usage: create-storage.sh env zone
# example value: ENV_NAME="fab", GCP_ZONE="us-west1-c"

cd "$( dirname "${BASH_SOURCE[0]}" )"
source env.sh "$@"

echo "create Google Cloud Filestore ${FILESTORE} at location ${GCP_ZONE}"
starttime=$(date +%s)

# create cloud filestore
check=$(gcloud filestore instances describe ${FILESTORE} --format="csv[no-heading](state)")
if [ "${check}" == "READY" ]; then
  echo "Filestore ${FILESTORE} already exists"
else
  echo "create filestore ${FILESTORE}"
  gcloud filestore instances create ${FILESTORE} --file-share=name="vol1",capacity=1TB --network=name="default"
fi

# capture filestore IP address
storeip=$(gcloud filestore instances describe ${FILESTORE} --format="csv[no-heading](networks.ipAddresses[0])")
echo "export STORE_IP=${storeip}" > ./config/env.sh
echo "export GKE_CLUSTER=${GKE_CLUSTER}" >> ./config/env.sh
echo "export GCP_ZONE=${GCP_ZONE}" >> ./config/env.sh
echo "export GCP_PROJECT=${GCP_PROJECT}" >> ./config/env.sh

echo "Filestore ${FILESTORE} created in $(($(date +%s)-starttime)) seconds."
