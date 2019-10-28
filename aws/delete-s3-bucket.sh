#!/bin/bash

cd "$( dirname "${BASH_SOURCE[0]}" )"
source env.sh

# check if the bucket exists already
aws s3api list-buckets --query "Buckets[].Name" --out text | grep ${S3_BUCKET}
if [ $? -eq 0 ]; then
  echo "delete s3 bucket ${S3_BUCKET}"
  aws s3api delete-bucket --bucket ${S3_BUCKET}
fi
