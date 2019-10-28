#!/bin/bash

cd "$( dirname "${BASH_SOURCE[0]}" )"
source env.sh

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

echo "configure S3_BUCKET for bastion host setup"
sed -i -e "s/^export S3_BUCKET=.*/export S3_BUCKET=${S3_BUCKET}/" ./setup/env.sh
