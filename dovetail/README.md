# Build and deploy Dovetail flows

When [Dovetail](https://github.com/TIBCOSoftware/dovetail-contrib/tree/master/hyperledger-fabric) is used to develop chaincode and client apps for Hyperledger Fabric, the Flogo flows can be built and deployed to Kubernetes locally or in cloud using scripts in this section.

## Build chaincode flow in cloud
Chaincode flow model can be edited using [TIBCO Flogo® Enterprise v2.8.0](https://docs.tibco.com/products/tibco-flogo-enterprise-2-8-0), and exported as a JSON file, e.g., [marble.json](./samples/marble/marble.json) in the samples folder.

First, start a Fabric network in one of the supported cloud services, e.g. Azure as described in [README](../az/README.md).  You can then build the chaincode as `CDS` format using the following script on the `bastion` host:
```
cd ${HOME}/fabric-operation/dovetail
./dovetail.sh build-cds -s ./samples/marble -j marble.json -c marble_cc -v 1.0
```
This will generate a `CDS` file: `/mnt/share/netop1.com/cli/marble_cc_1.0.cds`, which can be installed and instantiated on a Fabric network hosted by any cloud service.

The above command used a sample chaincode downloaded from `Github` during the initialization of the `bastion` host.  If you want to build a new chaincode on your local workstation, however, you can use the utility script to upload your chaincode flow model from local workstation to the `bastion` host, and then build it, e.g. for Azure,
```
cd /path/to/local/fabric-operation/az
./az-util.sh upload-folder -f /path/to/local/dovetail-contrib/hyperledger-fabric/samples/audit
```
This will upload the `audit` sample in the local `dovetail-coontrib` project to the `${HOME}` directory of the `bastion` host in Azure.  You can then build the `CDS` file, `audit_cc_1.0.cds` on the Azure `bastion` host:
```
cd ${HOME}/fabric-operation/dovetail
./dovetail.sh build-cds -s ~/audit -j audit.json -c audit_cc
```
You can then download the `CDS` file from the `bastion` host, and so the same chaincode can be installed/instantiated any other Fabric network:
```
cd /path/to/local/fabric-operation/az
./az-util.sh download-file -f /mnt/share/netop1.com/cli/audit_cc_1.0.cds -l /path/to/download
```

## Install and instantiate chaincode
The `CDS` file can be used to install and instantiate the chaincode on a Fabric network. The script for chaincode management is described in [network](../network/README.md).  To see how it works, you can create a test channel, and then instantiate the `marble_cc_1.0.cds` as follows:
```
cd ../network
# smoke test to create mychannel and join both peer nodes
./network.sh test

# install cds file from cli working folder, which is created during the build step
./network.sh install-chaincode -n peer-0 -f marble_cc_1.0.cds
./network.sh install-chaincode -n peer-1 -f marble_cc_1.0.cds

# instantiate the chaincode
./network.sh instantiate-chaincode -n peer-0 -c mychannel -s marble_cc -v 1.0 -m '{"Args":["init"]}'
```

## Configure Flogo Enterprise components
The above build process will fail if the chaincode flow model uses any component of the Flogo Enterprise, including a function, activity or trigger that is not an open-source Flogo component.  To build such chaincode flows, you must first upload the Flogo Enterprise installer zip file to the `bastion` host, e.g., for Azure,
```
# delete large studio docker image from Flogo Enterprise installer zip
zip -d /path/to/download/TIB_flogo_2.8.0_macosx_x86_64.zip "**/docker/flogo-studio-image.tar" 

# upload installer zip to bastion host
cd /path/to/local/fabric-operation/az
./az-util.sh upload-file -f /path/to/download/TIB_flogo_2.8.0_macosx_x86_64.zip
```
Then, run the installation script on the `bastion` host:
```
cd ${HOME}/fabric-operation/dovetail
./dovetail.sh install-fe -s ~/TIB_flogo_2.8.0_macosx_x86_64.zip
```
Note that you must have a TIBCO logon to download the installer zip for Flogo Enterprise.

## Build client app flow and deploy as Kubernetes service
Fabric client flows modeled using Flogo Enterprise can also be built locally or in cloud on a `bastion` host, and then running as a Kubernetes service.  The following scripts can be used on `bastion` host of any supported cloud environment, i.e., [Azure](../az), [AWS](../aws), or [GCP](../gcp).
```
# generate network config file if it is not already created
cd ${HOME}/fabric-operation/service
./gateway.sh config

# config app flows with default Fabric network yaml
cd ../dovetail
./dovetail.sh config-app -j ./samples/marble_client/marble_client.json

# start 2 instances of sample marble-client and expose end-point using a load-balancer service
./dovetail.sh start-app -j marble_client.json

# shutdown marble-client PODs and load-balancer service
./dovetail.sh stop-app -j marble_client.json
```

When the above script is invoked on a `bastion` host, it will interact with the blockchain network in corresponding cloud platform.  To run the same script on local Kubernetes of `Docker Desktop`, you need to specify the following 2 env variables:
```
# Git repo location of dovetail-contrib for Hyperledger Fabric
export DT_HOME=/path/to/dovetail-contrib/hyperledger-fabric

# Installation folder of Flogo Enterprise (needed for flogo models that use Flogo Enterprise components)
export FE_HOME=/path/to/flogo/2.8
```
## Configure client services in multi-org network
When a Fabric network contains multiple participating organizations, each organization may start its own orderer and/or peer nodes, and each organization may also run its own client services.

A network operator can start a Fabric network with a single organization, and then invite more organizations to join the network.  New organizations can be added to the network using scripts described [here](../operations.md#add-new-peer-org-to-the-same-kubernetes-cluster).

To configure a client service that interact with peer nodes of multiple organizations, you can run the following scripts to create a network config file containing list of peers from multiple organizations:
```
cd ../service
# create network config file for 2 different orgs
./gateway.sh config -p netop1 -c mychannel
./gateway.sh config -p peerorg1 -c mychnnel

# add peerorg1 peers to config file for netop1
yq m ../netop1.com/gateway/config/config_mychannel.yaml ../peerorg1.com/gateway/config/config_mychannel.yaml > /tmp/config_mychannel.yaml
cp /tmp/config_mychannel.yaml ../netop1.com/gateway/config

# copy crypto data of peerorg1 for the client service (only TLS certs are required, private user data should not be copied)
cp -R ../peerorg1.com/gateway/peerorg1.com ../netop1.com/gateway

# use the new network config file to configure client service, e.g.
cd ../dovetail
./dovetail.sh config-app -p netop1 -j ./samples/marble_client/marble_client.json
```
Note that the above script uses a tool `yq` for merging 2 `yaml` files, which can be downloaded as follows, e.g., for Mac,
```
curl -OL https://github.com/mikefarah/yq/releases/download/2.4.1/yq_darwin_amd64
chmod +x yq_darwin_amd64
sudo mv yq_darwin_amd64 /usr/local/yq
```