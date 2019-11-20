# Setup Microsoft Azure AKS cluster

The scripts in this section will launch an AKS cluster, setup Azure Files for persistence, and configure a `bastion` host that you can login and start a Hyperledger Fabric network.  The configuration file [env.sh](./env.sh) specifies the number and type of Azure VM instances and type of storage used by the AKS cluster, e.g., 3 VM instances are used by the default configuration.

## Configure Azure account login
Install [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest) as described by the link.

Once your Azure account is setup, you can login by typing the command:
```
az login
```
Enter your account info in a pop-up browser window.  Note that you may lookup your account details by using the [Azure Portal](https://portal.azure.com), although it is not absolutely necessary since we use only `Azure CLI` scripts.

## Start AKS cluster
Create and start the AKS cluster with all defaults:
```
cd ./az
./az-util.sh create
```
This script accepts 2 parameters for you to specify a different Azure environment, e.g.,
```
./az-util.sh create -n fab -r westus2
```
would create an AKS cluster with name prefix of `fab`, at the Azure location of `westus2`.

Wait 10 minutes for the cluster nodes to startup.  When the cluster is up, it will print a line, such as:
```
ssh fab@51.143.17.95
```
You can use this command to login to the `bastion` VM instance and create a Hyperledger Fabric network in the AKS cluster. Note that the `ssh` keypair for accessing the `bastion` host is in your `$HOME/.ssh` folder, and named as `id_rsa.pub` and `id_rsa`.  The script will generate a new keypair if these files do not exist already.  

Note also that the scripts have set the security group such that the `bastion` host can be accessed by only your workstation's current IP address. If your IP address changes, you'll need to login to Azure to update the security rule, or simply re-run the script:
```
cd ./az
az login
./create-bastion.sh fab westus2
```
## Prepare AKS cluster and Azure File storage for Hyperledger Fabric
Log on to the `bastion` host, e.g., (your real host IP will be different):
```
ssh fab@51.143.17.95
```
After login, you'll notice that everything is automatically setup for you.  You may verify the following configurations.
* `df` command should show that an `Azure File` storage is already mounted at `/mnt/share`;
* `kubectl get pod,svc --all-namespaces` should show you the Kubernetes system services and PODs;
* `ls ~` should show you that the latest code of this project is already downloaded at `$HOME/fabric-operation`.

## Start and test Hyperledger Fabric network
Following steps will start and smoke test the default Hyperledger Fabric network with 2 peers, and 3 orderers using `etcd raft` consensus. You can learn more details about these commands [here](../README.md).

### Create namespace for the network operator
```
cd ./fabric-operation/namespace
./k8s-namespace.sh create -t az
```
This command creates a namespace for the default Fabric operator company, `netop1`, and sets it as the default namespace.  It also creates Kubernetes secret for accessing Azure Files storage for persistence.  You can verify this step using the following commands:
* `kubectl get namespaces` should show a list of namespaces, including the new namespace `netop1`;
* `kubectl get secret` should show that a secret named `azure-secret` is created;
* `kubectl config current-context` should show that the default namespace is set to `netop1`.

### Start CA server and create crypto data for the Fabric network
```
cd ../ca
./ca-server.sh start -t az
# wait until 3 ca server and client PODs are in running state
./ca-crypto.sh bootstrap -t az
```
This command starts 2 CA servers and a CA client, and generates crypto data according to the network specification, [netop1.env](../config/netop1.env).  You can verify the result using the following commands:
* `kubectl get pods` should list 3 running PODs: `ca-server`, `tlsca-server`, and `ca-client`;
* `ls /mnt/share/netop1.com/` should list folders containing crypto data, i.e., `crypto`, `orderers`, `peers`, `cli`, and `tool`.

### Generate genesis block and channel creation tx
```
cd ../msp
./msp-util.sh start -t az
# wait until the tool POD is in running state
./msp-util.sh bootstrap -t az
```
This command starts a Kubernetes POD to generate the genesis block and transaction for creating a test channel `mychannel` based on the network specification.  You can verify the result using the following commands:
* `kubectl get pods` should list a running POD `tool`;
* `ls /mnt/share/netop1.com/tool` should show the generated artifacts: `genesis.block`, `channel.tx`, `anchors.tx`, and `configtx.yaml`.

### Start Fabric network
```
cd ../network
./network.sh start -t az
```
This command starts the orderers and peers using the crypto and genesis block created in the previous steps.  You can verify the network status using the following commands:
* `kubectl get pods` should list 3 running orderers and 2 running peers;
* `kubectl logs orderer-2` should show that a raft leader is elected by all 3 orderer nodes;
* `kubectl logs peer-1 -c peer` should show the logs of `peer-1`, that shows its successfully completed gossip communications with `peer-0`.
* `ls /mnt/share/netop1.com/orderers/orderer-0/data` shows persistent storage of the `orderer-0`, similar to other orderer nodes;
* `ls /mnt/share/netop1.com/peers/peer-0/data` shows persistent storage of the `peer-0`, similar to other peer nodes.

### Smoke test of the Fabric network
```
cd ../network
./network.sh test -t az
```
This command creates the test channel `mychannel`, installs and instantiates a test chaincode, and then executes a transaction and a query to verify the working network.  You can verify the result as follows:
* The last result printed out by the test should be `90`;
* Orderer data folder, e.g., `/mnt/share/netop1.com/orderers/orderer-0/data` would show a block file added under the chain of a new channel `chains/mychannel`;
* Peer data folder, e.g., `/mnt/share/netop1.com/peers/peer-0/data` would show a new chaincode `mycc.1.0` added to the `chaincodes` folder, and a transaction block file created under `ledgersData/chains/chains/mychannel`.

### Stop Fabric network and cleanup persistent data
```
cd ../network
./network.sh shutdown -t az -d
```
This command shuts down orderers and peers, and the last argument `-d` means to delete all persistent data as well.  If you do not use the argument `-d`, it would keep the test ledger file in the `Azure Files` storage, and so it can be loaded when the network restarts.  You can verify the result using the following command.
* `kubectl get svc,pod` should not list any running orderers or peers;
* The orderers and peers' persistent data folder, e.g., `/mnt/share/netop1.com/peers/peer-0/data` would be deleted if the option `-d` us used.

## Clean up all Azure processes and storage
You can exit from the `bastion` host, and clean up every thing created in Azure when they are no longer used, i.e.,
```
cd ./az
./az-util.sh cleanup -n fab -r westus2
```
This will clean up the AKS cluster and the Azure Files storage created in the previous steps.  Make sure that you supply the same parameters as that of the previous `az-util.sh create` command if they are different from the default values.

## TIPs

### Use kubectl from localhost
If your local workstation has `kubctl` installed, and you want to execute `kubectl` commands directly from the localhost, instead of going through the `bastion` host, you can set the env,
```
export KUBECONFIG=/path/to/fabric-operation/az/config/config-fab.yaml
```
where the `/path/to` is the location of this project on your localhost, and `config-fab.yaml` is named after the `ENV_NAME` specified in [`env.sh`](./env.sh).  The file is created for you when you execute `az-util.sh create`, and it is valid only while the AKS cluster is running.

You can then use `kubectl` commands against the Azure AKS cluster from your localhost directly, e.g.,
```
kubectl get pod,svc --all-namespaces
```
### Set default Kubernetes namespace
The containers created by the scripts will use the name of a specified operating company, e.g., `netop1`, as the Kubernetes namespace.  To save you from repeatedly typing the namespace in `kubectl` commands, you can set `netop1` as the default namespace by using the following commands:
```
kubectl config view
kubectl config set-context netop1 --namespace=netop1 --cluster=fabAKSCluster --user=clusterUser_fabRG_fabAKSCluster
kubectl config use-context netop1
```
Note to replace the values of `cluster` and `user` in the second command by the corresponding output from the first command.  This configuration is automatically done on the bastion host when the [`k8s-namespace.sh create`](../namespace/k8s-namespace.sh) script is called.