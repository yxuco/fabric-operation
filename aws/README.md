# Setup Amazon EKS cluster

The scripts of this section will launch an EKS cluster, setup a EFS file system for persistence, and configure a `bastion` host that you can login and start a Hyperledger Fabric network.  The configuration file [env.sh](.env.sh) specifies the number and type of EC2 instances by the EKS cluster, e.g., 3 `t2.medium` instances are used by the default configuration.

## Configure AWS account connection
Install AWS [CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-install.html) if you have not already done so.  Mac users can use the [bundled installer](https://docs.aws.amazon.com/cli/latest/userguide/install-macos.html).

Create AWS user `access key` if you do not already have one or do not remember the key.  In a web browser, login to [IAM console](https://console.aws.amazon.com/iam/home). On the user page, `Users > your-name@your-company.com`, choose `Security credentials` tab, and click `Create access key`. Take a note of the key-id and access-key before closing the window, and use the following AWS CLI command to configure your AWS connection:
```
aws configure
```
It should record the AWS configuration in 2 files in your local home directory, i.e., `$HOME/.aws/config`, which looks similar to the following:
```
[default]
region = us-west-2
output = json

[profile prod]
role_arn = arn:aws:iam::123456789012:role/TIBCO/Administrator
source_profile = default
region = us-west-2
output = json
```
and `$HOME/.aws/credentials`, which looks like
```
[default]
aws_access_key_id = ABCDEFGHIJ1234567890
aws_secret_access_key = abcdefghijklmnopqrstuvwxyz1234567890ABCD
```
If you need to work with a role for a different AWS account, you can add a `profile` definition to the `config` file, similar to the `prod` profile in the above sample.  To use the profile `prod` as the default, you can set the environment varialbe, e.g.,
```
export AWS_PROFILE=prod
```
## Start EKS cluster
Create and start the EKS cluster with all defaults:
```
cd ./aws
./create-all.sh
```
This script accepts 3 parameters for you to specify a different AWS environment, e.g.,
```
./create-all.sh fab us-west-2 prod
```
would create a EKS cluster with name prefix of `fab`, in the AWS region of `us-west-2`, using AWS account profile `prod`.

Wait 20-30 minutes for the cluster nodes to startup.  When the cluster is up, it will print out a line, such as:
```
ssh -i ./config/fab-keypair.pem ec2-user@ec2-34-213-140-181.us-west-2.compute.amazonaws.com
```
You can use this command to login to the `bastion` EC2 instance and create a Hyperledger Fabric network in the EKS cluster.  You may need to set the env variable `AWS_PROFILE` if you need to work as a different AWS role.

## Prepare EKS cluster and EFS file system for Hyperledger Fabric
Log on to the `bastion` host, e.g., (your real host name will be different):
```
ssh -i ./config/fab-keypair.pem ec2-user@ec2-34-213-140-181.us-west-2.compute.amazonaws.com
```
Setup working environment, install CSI driver for EFS, and download this project from `github.com`, i.e.,
```
. ./env.sh
kubectl apply -k "github.com/kubernetes-sigs/aws-efs-csi-driver/deploy/kubernetes/overlays/stable/?ref=master"
git clone https://github.com/yxuco/fabric-operation.git
```
The [~/env.sh](./setup/env.sh) contains 2 variables that specify the EFS file system providing the ledger storage for the fabric network, e.g.,
```
export AWS_MOUNT_POINT=opt/share
export AWS_FSID=fs-aec3d805
```
The values in this file will be different everytime you restart the system, and they must be used to replace the corresponding values in the downloaded `fabric-operation` config file, i.e., [`~/fabric-operation/config/setup.sh](../config/setup.sh).

Verify that the EFS CSI driver is installed successfully, i.e., the following pods are running:
```
$ kubectl get pod,svc --all-namespaces

kube-system   efs-csi-node-7qr9p              3/3     Running             0          39s
kube-system   efs-csi-node-8c94c              3/3     Running             0          39s
kube-system   efs-csi-node-cg224              3/3     Running             0          39s
```
You can now follow the steps [here](../README.md) to build and start a Hyperledger Fabric network.

## TIP
The containers created by the scripts will use the name of the sample operating company, `netop1`, as the Kubernetes namespace.  To save you from repeatedly typing the namespace in `kubectl` commands, you can set the namespace `netop1` as the default by using the following commands:
```
kubectl config view
kubectl config set-context netop1 --namespace=netop1 --cluster=fab-eks-stack.us-west-2.eksctl.io --user=1572660907000277000@fab-eks-stack.us-west-2.eksctl.io
kubectl config use-context netop1
```
Note to replace the values of `cluster` and `user` in the second command by the corresponding output from the first command.