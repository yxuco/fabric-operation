# CA crypto utility

This utility uses 2 [fabric-ca](https://hyperledger-fabric-ca.readthedocs.io/en/release-1.4/) servers to generate crypto data for Hyperledger Fabric users and nodes.  One server is used to generate CA keys, another is used to generate TLS keys.

## Start CA servers and client containers
Example:
```
cd ./ca
./ca-server.sh start -p netop1 -t k8s
```
This starts the fabric-ca server and client containers using the config file [netop1.env](../config/netop1.env), which must be configured and put in the [config](../config) folder.  The containers will be running in `docker-desktop` Kubernetes on Mac.  Non-Mac users should specify a different `-t` value to run it in another environment supported by your platform. The following command prints out the supported options:
```
./ca-server.sh -h

Usage:
  ca-server.sh <cmd> [-p <property file>] [-t <env type>] [-d]
    <cmd> - one of 'start', or 'shutdown'
      - 'start' - start ca and tlsca servers and ca client
      - 'shutdown' - shutdown ca and tlsca servers and ca client, and cleanup ca-client data
    -p <property file> - the .env file in config folder that defines network properties, e.g., netop1 (default)
    -t <env type> - deployment environment type: one of 'docker', 'k8s' (default), 'aws', or 'az'
    -d - delete all ca/tlsca server data for fresh start next time
  ca-server.sh -h (print this message)
```
* Docker-compose users can use option `-t docker`
* Azure users can refer instructions in the folder [az](../az) to run it from an Azure `bastion` VM instance with option `-t az`.
* AWS users can refer instructions in the folder [aws](../aws) to run it from an Amazon `bastion` EC2 instance with option `-t aws`.

## Bootstrap crypto of all nodes and users
Example:
```
cd ./ca
./ca-crypto.sh bootstrap -p netop1 -t k8s
```
This uses the `ca-client` container to generate crypto data for all peers, orderers, and users specified by the network specification file [netop1.env](../config/netop1.env). The result is stored in the folder [netop1.com](../netop1.com). The following command prints out other options:
```
./ca-crypto.sh -h

Usage:
  ca-crypto.sh <cmd> [-p <property file>] [-t <env type>] [-s <start seq>] [-e <end seq>] [-u <user name>]
    <cmd> - one of 'bootstrap', 'orderer', 'peer', 'admin', or 'user'
      - 'bootstrap' - generate crypto for all orderers, peers, and users in a network spec
      - 'orderer' - generate crypto for specified orderers
      - 'peer' - generate crypto for specified peers
      - 'admin' - generate crypto for specified admin users
      - 'user' - generate crypto for specified client users
    -p <property file> - the .env file in config folder that defines network properties, e.g., netop1 (default)
    -t <env type> - deployment environment type: one of 'docker', 'k8s' (default), 'aws', or 'az'
    -s <start seq> - start sequence number (inclusive) for orderer or peer
    -e <end seq> - end sequence number (exclusive) for orderer or peer
    -u <user name> - space-delimited admin/client user names
  ca-crypto.sh -h (print this message)
```
When this command is used on `AWS` or `Azure`, the generated crypto data will be stored in a cloud file system mounted on the `bastion` host, e.g., a mounted folder `/mnt/share/netop1.com` in an `EFS` file system on `AWS` or an `Azure Files` storage on `Azure`.

## Add crypto of new orderer nodes
Example:
```
cd ./ca
./ca-crypto.sh orderer -p netop1 -t k8s -s 3 -e 5
```
This will create crypto data for 2 new orderer nodes, `orderer-3` and `orderer-4`.

## Add crypto of new peer nodes
Example:
```
cd ./ca
./ca-crypto.sh peer -p netop1 -t k8s -s 2 -e 4
```
This will create crypto data for 2 new peer nodes, `peer-2` and `peer-3`.

## Add crypto of new client users
Example:
```
cd ./ca
./ca-crypto.sh user -p netop1 -t k8s -u "Carol David"
```
This will create crypto data for 2 new client users, `Carol@netop1.com` and `David@netop1.com`.

Note that the current implementation specifies only a couple of fixed attributes in user certificates. You may customize the attributes if your application requires.  We may enhance the scripts in the future to make it easier to customize user attributes.

## Add crypto of new admin users
Example:
```
cd ./ca
./ca-crypto.sh admin -p netop1 -t k8s -u "Super Hero"
```
This will create crypto data for 2 new admin users, `Super@netop1.com` and `Hero@netop1.com`.

## Shutdown and cleanup
Example:
```
cd ./ca
./ca-server.sh shutdown -p netop1 -t k8s
```
This shuts down the ca-server and ca-client containers, but keeps the state of 2 ca servers, so you can add more users/nodes using the same root CA.  If you want to delete all state and start from scratch, however, you can add the option `-d` when shuting down the servers.  You should keep a copy of the ca-server folders, e.g., `netop1.com/canet/ca-server` and `netop1.com/canet/tlsca-server`, if you want to generate additional crypto data for a running Fabric network.