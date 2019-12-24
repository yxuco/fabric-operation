# Build and deploy Dovetail flows to cloud

When [Dovetail](https://github.com/TIBCOSoftware/dovetail-contrib/tree/master/hyperledger-fabric) is used to develop chaincode and client apps for Hyperledger Fabric, the Flogo flows can be built and deployed to cloud using scripts in this section.

## Build chaincode flow
Chaincode flow model can be edited using [TIBCO Flogo® Enterprise v2.8.0](https://docs.tibco.com/products/tibco-flogo-enterprise-2-8-0), and exported as a JSON file, e.g., [marble.json](./samples/marble/marble.json) in the samples folder.

First, start a Fabric network in one of the supported cloud services, e.g. Azure as described in [README](../az/README.md).  You can then build the chaincode as `CDS` format using the following script on the `bastion` host:
```
cd ${HOME}/fabric-operation/dovetail
./dovetail.sh build-cds -s $PWD/samples/marble -j marble.json -c marble_cc -v 1.0
```
This will generate a `CDS` file: `${HOME}/marble_cc_1.0.cds`, which can be installed and instantiated on a Fabric network hosted by any cloud service.

The above command used a sample chaincode downloaded from `Github` during the initialization of the `bastion` host.  If you want to build a new chaincode on your local workstation, however, you can use the utility script to upload your chaincode flow model from local workstation to the `bastion` host, and then build it, e.g. for Azure,
```
cd /path/to/local/fabric-operation/az
./az-util.sh upload-folder -f /path/to/local/dovetail-contrib/hyperledger-fabric/samples/audit
```
This will upload the `audit` sample in the local `dovetail-coontrib` project to the `${HOME}` directory of the `bastion` host in Azure.  You can then build the `CDS` file, `audit_cc_1.0.cds` on the Azure `bastion` host:
```
cd ${HOME}/fabric-operation/dovetail
./dovetail.sh build-cds -s audit -j audit.json -c audit_cc
```
You can then download the `CDS` file from the `bastion` host, and so the same chaincode can be installed/instantiated any other Fabric network:
```
cd /path/to/local/fabric-operation/az
./az-util.sh download-file -f audit_cc_1.0.cds -l /path/to/download
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
./dovetail.sh install-fe -s TIB_flogo_2.8.0_macosx_x86_64.zip
```
Note that you must have a TIBCO logon to download the installer zip for Flogo Enterprise.

## Build client app flow
Fabric client flows modeled using Flogo Enterprise can also be built on the `bastion` host simillarly, e.g.,
```
cd ${HOME}/fabric-operation/dovetail
./dovetail.sh build-app -j $PWD/samples/marble_client/marble_client.json -c marble_client -o linux
```
This command builds the sample flow `marble_client.json`, and creates an executable for `linux`: `${HOME}/marble_client_linux_amd64`.  You may upload any client flow `JSON` file to the `bastion` host and build an executable for `linux` or other hardware platform, e.g., `darwin` for Mac.

TODO: deploy client app as Kubernetes service in the cloud, similar to the gateway [service](../service/README.md).