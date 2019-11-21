#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

# create AWS key-pair used by EKS and EFS, only if it does not exist already

cd "$( dirname "${BASH_SOURCE[0]}" )"
source env.sh "$@"

function createKeyPair {
  # check key pair if it exists
  local awsKey=$(aws ec2 describe-key-pairs --key-names ${KEYNAME} --query KeyPairs[0].KeyFingerprint --output text)
  echo "aws finger: ${awsKey}"
  if [ -f ${SSH_PRIVKEY} ]; then
    local fileKey=$(openssl pkcs8 -in ${SSH_PRIVKEY} -inform PEM -outform DER -topk8 -nocrypt | openssl sha1 -c)
    echo "file finger: ${fileKey}"
    if [ ! -z ${awsKey} ] && [ "${awsKey}" == "${fileKey}" ]; then
      echo "key pair ${KEYNAME} already defined in ${SSH_PRIVKEY}"
      return
    fi
    echo "cleanup local key file ${SSH_PRIVKEY}"
    rm -f ${SSH_PRIVKEY}
  fi
  if [ ! -z ${awsKey} ]; then
    echo "delete aws key ${KEYNAME}"
    aws ec2 delete-key-pair --key-name ${KEYNAME}
  fi

  echo "create new key pair ${KEYNAME}"
  aws ec2 create-key-pair --key-name ${KEYNAME} --query 'KeyMaterial' --output text > ${SSH_PRIVKEY}
  chmod 400 ${SSH_PRIVKEY}
  ssh-keygen -y -f ${SSH_PRIVKEY} > ${SSH_PUBKEY}
  echo "downloaded key pair in ${SSH_PRIVKEY}"
}

# create key pair for managing EFS
createKeyPair
