#!/bin/bash
# create Azure store account secret and setup Kubernetes for a specified namespace
# usage: ./kube-setup.sh <namespace>

source ./env.sh

# default namespace for sample fabric org
ns=${1:-"netop1"}

# create azure-secret yaml
function printAzureSecretYaml {
  user=$(echo -n "${STORAGE_ACCT}" | base64 -w 0)
  key=$(echo -n "${STORAGE_KEY}" | base64 -w 0)
  echo "
apiVersion: v1
kind: Namespace
metadata:
  name: ${ns}
  labels:
    use: hyperledger
---
apiVersion: v1
kind: Secret
metadata:
  name: azure-secret
  namespace: ${ns}
type: Opaque
data:
  azurestorageaccountname: ${user}
  azurestorageaccountkey: ${key}"
}

# create secret for Azure File storage
printAzureSecretYaml > ${HOME}/azure-secret.yaml
kubectl create -f ${HOME}/azure-secret.yaml

# set default namespace
kubectl config set-context ${ns} --namespace=${ns} --cluster=${AKS_CLUSTER} --user=clusterUser_${RESOURCE_GROUP}_${AKS_CLUSTER}
kubectl config use-context ${ns}
