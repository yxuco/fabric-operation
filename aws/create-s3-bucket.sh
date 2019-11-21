#!/bin/bash
# Copyright © 2018. TIBCO Software Inc.
#
# This file is subject to the license terms contained
# in the license file that is distributed with this file.

cd "$( dirname "${BASH_SOURCE[0]}" )"
source env.sh "$@"

# check if the bucket exists already
aws s3api list-buckets --query "Buckets[].Name" --out text | grep ${S3_BUCKET}
if [ $? -ne 0 ]; then
  region=$(aws configure get region)
  echo "create s3 bucket ${S3_BUCKET} in region ${region}"
  aws s3api create-bucket --bucket ${S3_BUCKET} --region ${region} --create-bucket-configuration LocationConstraint=${region}
  aws s3api put-bucket-acl --bucket ${S3_BUCKET} --grant-read uri=http://acs.amazonaws.com/groups/global/AllUsers
  aws s3api put-bucket-acl --bucket ${S3_BUCKET} --acl public-read
else
  echo "s3 bucket ${S3_BUCKET} already exists, skip."
fi
