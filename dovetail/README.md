# Build and Deploy Dovetail flows to Cloud

When [Dovetail](https://github.com/TIBCOSoftware/dovetail-contrib/tree/master/hyperledger-fabric) is used to develop chaincode and client apps for Hyperledger Fabric, the Flogo flows can be built and deployed to cloud using scripts in this section.

## Build Chaincode Flow
Chaincode flow model can be edited using [TIBCO Flogo® Enterprise v2.8.0](https://docs.tibco.com/products/tibco-flogo-enterprise-2-8-0), and exported as a JSON file, e.g., [marble.json](./samples/marble/marble.json) in the samples folder.

First, start a Fabric in one of the supported cloud services, e.g. Azure as described in [README](../az/README.md).  You can then build the chaincode as `CDS` format using the following script on the `bastion` host:
```
cd ${HOME}/fabric-operation/dovetail
./dovetail.sh build-cds -s $PWD/samples/marble -j marble.json -c marble_cc -v 1.0
```
This will generate a `CDS` file: `${HOME}/marble_cc_1.0.cds`, which can be installed and instantiated on a Fabric network running on any cloud services.

The above command used a sample chaincode downloaded from `Github` during the initialization of the `bastion` host.  If you want to build a new chaincode on your local workstation, however, you can use the utility script to upload your chaincode flow from local workstation to the bastion host, and then build it, e.g. for Azure,
```
cd /path/to/local/fabric-operation/az
./az-util.sh upload-folder -f /path/to/local/dovetail-contrib/hyperledger-fabric/samples/audit
```
This will upload the `audit` sample in the local `dovetail-coontrib` project to the `${HOME}` directory of the `bastion` host in Azure.  You can then build the `CDS` file, `audit_cc_1.0.cds` on the Azure `bastion` host:
```
cd ${HOME}/fabric-operation/dovetail
./dovetail.sh build-cds -s audit -j audit.json -c audit_cc
```
You can then download the `CDS` file from the `bastion` host, and so the same chaincode can be installed/instantiated in any other supported cloud services:
```
cd /path/to/local/fabric-operation/az
./az-util.sh download-file -f audit_cc_1.0.cds -l /path/to/download
```
## Configure Flogo Enterprise Components
The above build process will fail if the chaincode flow model uses any component of the Flogo Enterprise, including a function, activity or trigger that is not an open-source Flogo component.  To build such chaincode flows, you must first upload the Flogo Enterprise installer zip file to the `bastion` host, e.g., for Azure,
```
cd /path/to/local/fabric-operation/az
./az-util.sh upload-file -f /path/to/download/TIB_flogo_2.8.0_macosx_x86_64.zip
```
Then, run the installation script on the `bastion` host:
```
cd ${HOME}/fabric-operation/dovetail
./dovetail.sh install-fe -s TIB_flogo_2.8.0_macosx_x86_64.zip
```
Note that you must have a TIBCO logon to download the installer zip for Flogo Enterprise.

## Build Client App Flow
Fabric client flows modeled using Flogo Enterprise can also be built on the `bastion` host simillarly, e.g.,
```
cd ${HOME}/fabric-operation/dovetail
./dovetail.sh build-app -j $PWD/samples/marble_client/marble_client.json -c marble_client -o linux
```
This command builds the sample flow `marble_client.json`, and creates an executable for `linux`: `${HOME}/marble_client_linux_amd64`.  You may upload any client flow `JSON` file to the `bastion` host and build an executable for `linux` or other hardware platform, e.g., `darwin` for Mac.

TODO: deploy client app as Kubernetes service in the cloud, similar to the gateway [service](../service/README.md)