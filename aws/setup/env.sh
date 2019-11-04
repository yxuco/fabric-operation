##### pre-configured variables in EKS/EFS/S3
##### they are populated by creation scrypts, so do not manually edit
export EKS_STACK=fab-eks-stack
export EFS_STACK=fab-efs-client
# used to mount EFS volume by NFS
export EFS_SERVER=fs-f0ff1a5a.efs.us-west-2.amazonaws.com
# name of the test environment
export ENV_NAME=fab
# used to share data across region and accounts
export S3_BUCKET=fab-s3-share
# used to setup bastion host
export MOUNT_POINT=opt/share
export SSH_PRIVKEY=fab-keypair.pem

# user role if creating network in an assumed role
export AWS_PROFILE=prod
export BASTION=ec2-54-218-11-119.us-west-2.compute.amazonaws.com

# these 2 variables should be copied to fabric setup script: ~fabric-operation/config/setup.sh
export AWS_MOUNT_POINT=opt/share
export AWS_FSID=fs-f0ff1a5a
