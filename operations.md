# Network operations
After a bootstrap Fabric network is started, you can use the following scripts to make your application and scale.

## Create new channel
When the smoke test is executed, the bootstrap network automatically creates a test channel, e.g., `mychannel` (as configured in the network spec, [netop1.env](./config/netop1.env)).  If can create new channels by using the following script:
```
# create channel config tx
cd ./msp
# start tool container if not already started
./msp-util.sh start -p netop1
./msp-util.sh channel -p netop1 -c "newchannel"

# create channel in the network
cd ../network
# start fabric network if not already started
./network.sh start -p netop1
./network.sh create-channel -p netop1 -c "newchannel"
```
This sample creates a channel named `newchannel`.

## Joine existing channel
After a channel is created, a peer node can join the channel using the following command:
```
cd ../network
# start fabric network if not already started
./network.sh start -p netop1
./network.sh join-channel -p netop1 -n peer-0 -c mychannel -a
```
This sample makes the peer `peer-0` to join channel named `mychannel`. The optional argument `-a` means to update the anchor peer for the organization, which can be used only if it is the first peer to join the channel.

## Install and instantiate new chaincode
To install new chaincode, first copy the chaincode folder to this project's [chaincode](./chaincode) folder, and then run the following script:
```
cd ../network
# start fabric network if not already started
./network.sh start -p netop1
./network.sh install-chaincode -p netop1 -n peer-0 -f chaincode_example02/go -s mycc -v 1.0 -a
./network.sh instantiate-chaincode -p netop1 -n peer-0 -c mychannel -s mycc -v 1.0 -m '{"Args":["init","a","100","b","200"]}'
```
This sample installs the chaincode in folder `./chaincode/chaincode_example02/go` on the peer node `peer-0` as `mycc:1.0`, and instantiates it on the channel `mychannel`.  The optional argument `-a` means to replace the original source code if if already exist in the `CLI` working folder.

Note that if an older version of the chaincode has already been installed on a peer, you'll have to specify a new version number.

More chaincode related operations include `upgrade-chaincode`, `query-chaincode`, and `invoke-chaincode`.  They are described in [network.sh](./network/README.md).

## Add new peer nodes of the same bootstrap org
Use the following script to scale up number of peer nodes:
```
# create crypto data for the new peers
cd ./ca
# start ca server/client if they are not already started
./ca-server.sh start -p netop1
./ca-crypto.sh peer -p netop1 -s 2 -e 4

# scale to 4 peer nodes
cd ../network
./network.sh scale-peer -p netop1 -r 4
```
This sample assumes that the bootstrap network is already running 2 peer nodes, i.e., `peer-0` and `peer-1`. To scale it to 4 nodes, we first generate the crypto data for `peer-2` and `peer-3`, and then start these 2 more peer nodes.

## Add new peer org to the same Kubernetes cluster
It involves multiple steps to add a new organization to a running network.  However, all steps are scripted to simplify the process.

First, bootstrap and test the network for `netop1` as described in [README.md](./README.md).

Second, bootstrap network nodes for a new organization, as defined in [peerorg1.env](./config/peerorg1.env), i.e.,
```
cd ./namespace
./k8s-namespace.sh create -p peerorg1
cd ../ca
./ca-server.sh start -p peerorg1
./ca-crypto.sh bootstrap -p peerorg1
cd ../msp
./msp-util.sh start -p peerorg1
./msp-util.sh bootstrap -p peerorg1
cd ../network
./network.sh start -p peerorg1
```

Now, we have Fabric nodes running for both organizations, and we want to set up peers of `peerorg1` to join the network of `netop1`.  Following are the steps:
```
# create new org config by the peerorg1's admin
cd ./msp
./msp-util.sh mspconfig -p peerorg1

# send the resulting config file - peerorg1MSP.json - to netop1 for approval
cp ../peerorg1.com/tool/peerorg1MSP.json ../netop1.com/cli

# netop1 admin user approves and updates the channel
cd ../network
# create update transaction for mychannel
./network.sh add-org-tx -p netop1 -o peerorg1MSP -c mychannel
# optionally sign the transaction, which is necessary only if there are more than one active orgs
./network.sh sign-transaction -p netop1 -f mychannel-peerorg1MSP.pb
# update channel config
./network.sh update-channel -p netop1 -f mychannel-peerorg1MSP.pb -c mychannel

# peerog1 can now join mychannel and execute transactions
./network.sh join-channel -p peerorg1 -n peer-0 -c mychannel
./network.sh install-chaincode -p peerorg1 -n peer-0 -f chaincode_example02/go -s mycc -v 1.0 -a
./network.sh query-chaincode -p peerorg1 -n peer-0 -c mychannel -s mycc -m '{"Args":["query","a"]}'
```
The above sequence of sample commands joined the 4 peer nodes from 2 organizations, `netop1` and `peerorg1` in the same Fabric network, and executed a query on `peer-0` of the new organization `peerorg1`, which should return the same result as queries on peer nodes of the original organization `netop1`.