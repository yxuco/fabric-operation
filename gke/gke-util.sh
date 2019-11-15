#!/bin/bash
# create GKE cluster and Cloud Filestore
# usage: gke-util.sh <cmd> [-n <name>] [-r <zone>]
# e.g., gke-util.sh create -n fab -r us-west1-c

cd "$( dirname "${BASH_SOURCE[0]}" )"

# Print the usage message
function printHelp() {
  echo "Usage: "
  echo "  gke-util.sh <cmd> [-n <name>] [-r <zone>]"
  echo "    <cmd> - one of 'create', or 'cleanup'"
  echo "      - 'create' - create GKE cluster and Cloud Filestore"
  echo "      - 'cleanup' - shutdown GKE cluster and cleanup Cloud Filestore"
  echo "    -n <name> - prefix name of GKE cluster, e.g., fab (default)"
  echo "    -r <zone> - GCP region and zone to host the cluster, e.g. 'us-west1-c' (default)"
  echo "  gke-util.sh -h (print this message)"
}

CMD=${1}
shift
while getopts "h?n:r:" opt; do
  case "$opt" in
  h | \?)
    printHelp
    exit 0
    ;;
  n)
    ENV_NAME=$OPTARG
    ;;
  r)
    GCP_ZONE=$OPTARG
    ;;
  esac
done

if [ -z "${ENV_NAME}" ]; then
  ENV_NAME="fab"
fi

if [ -z "${GCP_ZONE}" ]; then
    GCP_ZONE="us-west1-c"
fi

case "${CMD}" in
create)
  echo "create GKE cluster - ENV_NAME: ${ENV_NAME}, GCP_ZONE: ${GCP_ZONE}"
  ./create-cluster.sh ${ENV_NAME} ${GCP_ZONE}
  ./create-storage.sh ${ENV_NAME} ${GCP_ZONE}
  ./create-bastion.sh ${ENV_NAME} ${GCP_ZONE}
  ;;
cleanup)
  echo "cleanup GKE cluster - ENV_NAME: ${ENV_NAME}, GCP_ZONE: ${GCP_ZONE}"
  source env.sh ${ENV_NAME} ${GCP_ZONE}

  starttime=$(date +%s)
  echo "cleanup may take 5 mminutes ..."

  echo "delete bastion host ${BASTION_HOST}"
  gcloud compute instances delete ${BASTION_HOST} --quiet
  echo "delete Cloud Filestore ${FILESTORE}"
  gcloud filestore instances delete ${FILESTORE} --quiet
  echo "delete GKE cluster ${GKE_CLUSTER}"
  gcloud container clusters delete ${GKE_CLUSTER} --quiet

  echo "Cleaned up ${GCP_PROJECT} in $(($(date +%s)-starttime)) seconds."
  ;;
*)
  printHelp
  exit 1
esac
