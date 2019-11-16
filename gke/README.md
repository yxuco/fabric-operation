# Setup Google cloud GKE cluster

The scripts in this section will launch a GKE cluster, setup Cloud Filestore for persistence, and configure a `bastion` host that you can login and start a Hyperledger Fabric network.  The configuration file [env.sh](./env.sh) specifies the Google cloud project, region and number of GKE nodes of the GKE cluster, e.g., 3 nodes are used by the default configuration.

## Configure Google Cloud account login
Install Google Cloud SDK: https://cloud.google.com/sdk/docs/quickstarts, which includes the `gcloud` utility that we installed in `$HOME` directory and used to script the configuration.

To get started, you need to create a Google project with billing enabled. On [GCP Console](https://console.cloud.google.com), click "My First Project", then in the popup window, click "NEW PROJECT" at top-right corner, then specify a new default project, e.g., fab-project-001, then click "CREATE" to create it.  We shall use this project to setup everything, so you can delete the project and associated artifacts when they are no longer used.

You can then login from your local workstation to setup the work environment:
```
gcloud auth login
gcloud projects list
```
Select your Google account in a pop-up browser window to login to Google Cloud.  The second command should list the project that we created on using the GCP Console.

## Start GKE cluster
Edit [env.sh](./env.sh) to upldate `GCP_PROJECT` to the name of the project created above or any existing project, and then create and start the GKE cluster with all defaults:
```
cd ./gke
./gke-util.sh create
```
This script accepts 2 parameters for you to specify a different Google cloud environment, e.g.,
```
./gke-util.sh create -n fab -r us-west1-c
```
would create an GKE cluster with name prefix of `fab`, in the GCP zone of `us-west1-c`.

Wait 7-8 minutes for the cluster nodes to startup.  When the cluster is up, it will print a line, such as:
```
gcloud compute ssh --ssh-key-file ./config/fab-key fab@fab-bastion
```
You can use this command to login to the `bastion` host and create a Hyperledger Fabric network using the GKE cluster. Note that the `ssh` keypair for accessing the `bastion` host is in the [config](./config) folder.

## Setup Google login from `bastion` host
Log on to the `bastion` host, and login to Google Cloud, e.g.,
```
gcloud compute ssh --ssh-key-file ./config/fab-key fab@fab-bastion
gcloud auth login
```
It will display a authentication url on the bastion window. Cut and paste the url from bastion to a browser to login, then cut and paste the verification code from browser to bastion window.

In the bastion window, use the following command to download GKE cluster config:
```
source ./env.sh
gcloud container clusters get-credentials ${GKE_CLUSTER} --zone ${GCP_ZONE}
```
You can then verify the following configurations.
* `df` command should show that a Google Cloud `Filestore` is already mounted at `/mnt/share`;
* `kubectl get pod,svc --all-namespaces` should show you the Kubernetes system services and PODs;
* `ls ~` should show you that the latest code of this project is already downloaded at `$HOME/fabric-operation`.

## Start and test Hyperledger Fabric network
Following steps will start and smoke test the default Hyperledger Fabric network with 2 peers, and 3 orderers using `etcd raft` consensus. You can learn more details about these commands [here](../README.md).

### Create namespace for the network operator
```
cd ./fabric-operation/namespace
./k8s-namespace.sh create -t gke
```
This command creates a namespace for the default Fabric operator company, `netop1`, and sets it as the default namespace.  It also creates Kubernetes secret for accessing Azure Files storage for persistence.  You can verify this step using the following commands:
* `kubectl get namespaces` should show a list of namespaces, including the new namespace `netop1`;
* `kubectl config current-context` should show that the default namespace is set to `netop1`.

### Start CA server and create crypto data for the Fabric network
```
cd ../ca
./ca-server.sh start -t gke
# wait until 3 ca server and client PODs are in running state
./ca-crypto.sh bootstrap -t gke
```
This command starts 2 CA servers and a CA client, and generates crypto data according to the network specification, [netop1.env](../config/netop1.env).  You can verify the result using the following commands:
* `kubectl get pods` should list 3 running PODs: `ca-server`, `tlsca-server`, and `ca-client`;
* `ls /mnt/share/netop1.com/` should list folders containing crypto data, i.e., `crypto`, `orderers`, `peers`, `cli`, and `tool`.

### Generate genesis block and channel creation tx
```
cd ../msp
./msp-util.sh start -t gke
# wait until the tool POD is in running state
./msp-util.sh bootstrap -t gke
```
This command starts a Kubernetes POD to generate the genesis block and transaction for creating a test channel `mychannel` based on the network specification.  You can verify the result using the following commands:
* `kubectl get pods` should list a running POD `tool`;
* `ls /mnt/share/netop1.com/tool` should show the generated artifacts: `genesis.block`, `channel.tx`, `anchors.tx`, and `configtx.yaml`.

### Start Fabric network
```
cd ../network
./network.sh start -t gke
```
This command starts the orderers and peers using the crypto and genesis block created in the previous steps.  You can verify the network status using the following commands:
* `kubectl get pods` should list 3 running orderers and 2 running peers;
* `kubectl logs peer-1 -c peer` should show the logs of `peer-1`, that shows its successfully completed gossip communications with `peer-0`.
* `ls /mnt/share/netop1.com/orderers/orderer-0/data` shows persistent storage of the `orderer-0`, similar to other orderer nodes;
* `ls /mnt/share/netop1.com/peers/peer-0/data` shows persistent storage of the `peer-0`, similar to other peer nodes.

### Smoke test of the Fabric network
```
cd ../network
./network.sh test -t gke
```
This command creates the test channel `mychannel`, installs and instantiates a test chaincode, and then executes a transaction and a query to verify the working network.  You can verify the result as follows:
* The last result printed out by the test should be `90`;
* Orderer data folder, e.g., `/mnt/share/netop1.com/orderers/orderer-0/data` would show a block file added under the chain of a new channel `chains/mychannel`;
* Peer data folder, e.g., `/mnt/share/netop1.com/peers/peer-0/data` would show a new chaincode `mycc.1.0` added to the `chaincodes` folder, and a transaction block file created under `ledgersData/chains/chains/mychannel`.

### Stop Fabric network and cleanup persistent data
```
cd ../network
./network.sh shutdown -t gke -d
```
This command shuts down orderers and peers, and the last argument `-d` means to delete all persistent data as well.  If you do not use the argument `-d`, it would keep the test ledger file in the Google Cloud `Filestore`, and so it can be loaded when the network restarts.  You can verify the result using the following command.
* `kubectl get svc,pod` should not list any running orderers or peers;
* The orderers and peers' persistent data folder, e.g., `/mnt/share/netop1.com/peers/peer-0/data` would be deleted if the option `-d` us used.

## Clean up all GKE processes and storage
You can exit from the `bastion` host, and clean up every thing created in GCP when they are no longer used, i.e.,
```
cd ./gke
./gke-util.sh cleanup -n fab -r us-west1-c
```
This will clean up the GKE cluster and the Cloud Filestore created in the previous steps.  Make sure that you supply the same parameters as that of the previous `gke-util.sh create` command if they are different from the default values.

## TIPs

### Use kubectl from localhost
If your local workstation has `kubctl` installed, and you want to execute `kubectl` commands directly from the localhost, instead of going through the `bastion` host, you can set the env,
```
export KUBECONFIG=/path/to/fabric-operation/gke/config/config-fab.yaml
```
where the `/path/to` is the location of this project on your localhost, and `config-fab.yaml` is named after the `ENV_NAME` specified in [`env.sh`](./env.sh).  The file is created for you when you execute `gke-util.sh create`, and it is valid only while the GKE cluster is running.

You can then use `kubectl` commands against the GKE cluster from your localhost directly, e.g.,
```
kubectl get pod,svc --all-namespaces
```
### Set default Kubernetes namespace
The containers created by the scripts will use the name of a specified operating company, e.g., `netop1`, as the Kubernetes namespace.  To save you from repeatedly typing the namespace in `kubectl` commands, you can set `netop1` as the default namespace by using the following commands:
```
kubectl config view
kubectl config set-context netop1 --namespace=netop1 --cluster=fab-cluster --user=clusterUser_fabRG_fabAKSCluster
kubectl config use-context netop1
```
Note to replace the values of `cluster` and `user` in the second command by the corresponding output from the first command.  This configuration is automatically done on the bastion host when the [`k8s-namespace.sh create`](../namespace/k8s-namespace.sh) script is called.