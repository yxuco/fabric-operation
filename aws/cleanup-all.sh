#!/bin/bash
# cleanup EKS cluster and associated EFS volume
# usage: cleanup-all.sh env region profile
# e.g., cleanup-all.sh dev us-west-2

cd "$( dirname "${BASH_SOURCE[0]}" )"
source env.sh "$@"

./cleanup-efs.sh
./cleanup-cluster.sh
#./delete-s3-bucket.sh

# cleanup EC2 volumes
vols=$(aws ec2 describe-volumes --filter Name=status,Values=available --query Volumes[*].VolumeId --out text)
array=( $vols )
for v in "${array[@]}"; do
  echo "delete EC2 volume $v"
  aws ec2 delete-volume --volume-id $v
done 
