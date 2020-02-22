# Build and deploy Dovetail flows

When [Dovetail](https://github.com/TIBCOSoftware/dovetail-contrib/tree/master/hyperledger-fabric) is used to develop chaincode and client apps for Hyperledger Fabric, the Flogo flows can be built and deployed to Kubernetes locally or in cloud using scripts in this section.

## Build chaincode flow in cloud

Chaincode flow model can be edited using [TIBCO Flogo® Enterprise v2.8.0](https://docs.tibco.com/products/tibco-flogo-enterprise-2-8-0), and exported as a JSON file, e.g., [marble.json](./samples/marble/marble.json) in the samples folder.

First, start a Fabric network in one of the supported cloud services, e.g. Azure as described in [README](../az/README.md).  You can then build the chaincode as `CDS` format using the following script on the `bastion` host:

```bash
cd ${HOME}/fabric-operation/msp
./msp-util.sh start

# wait until tool container is running
./msp-util.sh build-cds -m ../dovetail/samples/marble/marble.json -v 1.0
```

This will generate a `CDS` file: `/mnt/share/netop1.com/tool/marble_cc_1.0.cds`, which can be installed and instantiated on a Fabric network hosted by any cloud service.

The above command used a sample chaincode downloaded from `Github` during the initialization of the `bastion` host.  If you want to build a new chaincode on your local workstation, however, you can use the utility script to upload your chaincode flow model from local workstation to the `bastion` host, and then build it, e.g. for Azure,

```bash
cd /path/to/local/fabric-operation/az
./az-util.sh upload-folder -f /path/to/local/dovetail-contrib/hyperledger-fabric/samples/audit
```

This will upload the `audit` sample in the local `dovetail-coontrib` project to the `${HOME}` directory of the `bastion` host in Azure.  You can then build the `CDS` file, `audit_cc_1.0.cds` on the Azure `bastion` host:

```bash
cd ${HOME}/fabric-operation/msp
./msp-util.sh build-cds -m ${HOME}/audit/audit.json
```

You can then download the `CDS` file from the `bastion` host, and so the same chaincode can be installed/instantiated any other Fabric network:

```bash
cd /path/to/local/fabric-operation/az
./az-util.sh download-file -f /mnt/share/netop1.com/tool/audit_cc_1.0.cds -l /path/to/download
```

For other cloud services, refer [AWS](../aws/README.md) and [GCP](../gcp/README.md) for similar commands.

If you have installed `docker` on your local host, you can also use the [dovetail-tool](https://github.com/TIBCOSoftware/dovetail-contrib/tree/master/hyperledger-fabric/dovetail-tools) to build chaincode `cds` package.

## Install and instantiate chaincode

The `CDS` file can be used to install and instantiate the chaincode on a Fabric network. The script for chaincode management is described in the [network](../network/README.md) folder.  To see how it works, you can create a test channel, and then instantiate the `marble_cc_1.0.cds` as follows:

```bash
cd ../network
# smoke test to create mychannel and join both peer nodes
./network.sh test

# install cds file from cli working folder, which is created during the build step
./network.sh install-chaincode -n peer-0 -f marble_cc_1.0.cds
./network.sh install-chaincode -n peer-1 -f marble_cc_1.0.cds

# instantiate the chaincode
./network.sh instantiate-chaincode -n peer-0 -c mychannel -s marble_cc -v 1.0 -m '{"Args":["init"]}'
```

## Build client app flow and deploy as Kubernetes service

Fabric client flows modeled using Flogo Enterprise can also be built in cloud on a `bastion` host, and then run as a Kubernetes service.  The following scripts can be used on a `bastion` host of any supported cloud environment, i.e., [Azure](../az), [AWS](../aws), or [GCP](../gcp).

```bash
# generate network config file if it is not already created
cd /path/to/fabric-operation/service
./gateway.sh config

# config app flow model to use the above configured Fabric network yaml
cd ../dovetail
./dovetail.sh config-app -m ./samples/marble_client/marble_client.json

# build the appp and start 2 PODs and expose end-point using a load-balancer service
./dovetail.sh start-app -m marble_client.json
```

When the above script is invoked on a `bastion` host, it will start 2 instances of `marble_client` and expose the service end-point as a load-balancer service in corresponding cloud platform.  When it is invoked on local Kubernetes of `Docker Desktop`, it will start 2 PODs for `marble_client` and expose the service end-point as a random `Node Port`.  The service URL is printed out by the script, e.g.,
```
access marble-client service at http://localhost:32634
```
Use this URL to send REST service requests to test the system.  

Finally, you can shutdown the client PODs and service using the following command:

```bash
./dovetail.sh stop-app -m marble_client.json
```

## Configure client services in multi-org network

When a Fabric network contains multiple participating organizations, each organization may start its own orderer and/or peer nodes, and each organization may also run its own client services.

A network operator can start a Fabric network with a single organization, and then invite more organizations to join the network.  New organizations can be added to the network using scripts described [here](../operations.md#add-new-peer-org-to-the-same-kubernetes-cluster).

To configure a client service that interact with peer nodes of multiple organizations, you can run the following scripts to create a network config file containing list of peers from multiple organizations:

```bash
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
./dovetail.sh config-app -p netop1 -m ./samples/marble_client/marble_client.json
```

Note that the above script uses a tool `yq` to merge 2 `yaml` files.  The tool can be downloaded as follows, e.g., for Mac,

```bash
curl -OL https://github.com/mikefarah/yq/releases/download/2.4.1/yq_darwin_amd64
chmod +x yq_darwin_amd64
sudo mv yq_darwin_amd64 /usr/local/yq
```
