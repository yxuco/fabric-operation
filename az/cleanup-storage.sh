#!/bin/bash
# cleanup Azure Files storage for a specified $ENV_NAME and $AZ_REGION
# usage: cleanup-storage.sh env region
# default value: ENV_NAME="fab", AZ_REGION="westus2"

cd "$( dirname "${BASH_SOURCE[0]}" )"
source env.sh "$@"

echo "delete Azure File storage ${STORAGE_ACCT}"
starttime=$(date +%s)

az storage account delete -n ${STORAGE_ACCT} -y
echo "Azure File storage ${STORAGE_ACCT} deleted in $(($(date +%s)-starttime)) seconds."
