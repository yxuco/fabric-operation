# Fabric gateway service

The gateway service is a generic Fabric client service that provides REST and gRPC APIs for other applications to query or invoke Fabric transactions.

## Build gateway service
If you use a cloud provider, i.e., `AWS`, `Azure`, or `GCP`, you can use a `bastion` host to build and test the gateway service, and thus you do not need to install anything on your local workstation.  Scripts are provided to setup the `bastion` host for each of the major cloud providers.  Refer to the folder for [AWS](../aws), [Azure](../az), or [GCP](../gcp) for more details.

To build the service from source code for local test, you need to install the following prerequisites:
* Download and install Go as described [here](https://golang.org/dl/)
* Download and install `protoc` as described [here](https://grpc.io/docs/quickstart/go/)
* Install protobuff plugin for REST over gRPC as described [here](https://github.com/grpc-ecosystem/grpc-gateway) i.e.,
```
go get -u github.com/grpc-ecosystem/grpc-gateway/protoc-gen-grpc-gateway
go get -u github.com/grpc-ecosystem/grpc-gateway/protoc-gen-swagger
```
You can then build and test the gateway service using the [Makefile](./Makefile), e.g.,
```
# clean and build for local test on Mac
make

# test using fabric-sample byfn, assuming that the fabric-sample is installed in $GOPATH/src/github.com/hyperledger/fabric-samples/first-network
make run

# build and copy for Kubernetes, assuming that fabric network is started using '../network/network.sh start'
make dist
```

## Start Fabric network using Kubernetes
Before starting the gateway service, you can follow the instructions in [README.md](../README.md) to bootstrap and start a sample Fabric network using Kubernetes, i.e.,
```
cd ../ca
./ca-server.sh start
./ca-crypto.sh bootstrap
cd ../msp
./msp-util.sh start
./msp-util.sh bootstrap
cd ../network
./network.sh start
./network.sh test
```
The above sequence of commands created a Fabric network from scratch, and deployed a sample chaincode `mycc` to a test channel `mychannel`.

## Start gateway service
Use the following commands to start 2 Kubernetes PODs to run the gateway service on Mac `docker-desktop`:
```
cd ../service
./gateway.sh start
```
On a Mac, this gateway service listens to REST requests on a `NodePort`: `30081`.  You can also run the service on a cloud provider.  The scripts support [AWS](../aws), [Azure](../az), and [GCP](../gcp).  Click one of the links to see how easy it is to start a Hyperledger Fabric network in the cloud, and expose the blockchain as a public service via this `gateway service`.

## Invoke Fabric transactions using Swagger-UI
Open the Swagger UI in Chrome web-browser: [http://localhost:30081/swagger](http://localhost:30081/swagger).

It defines 2 REST APIs:
* **Connection**, which creates or finds a Fabric network connection, and returns the connection-ID.
* **Transaction**, which invokes a Fabric transaction for query or invocation on a specified or randomly chosen endpoint.

Click `Try it out` for `/v1/connection`, and execute the following request
```
{
  "channel_id": "mychannel",
  "user_name": "Admin",
  "org_name": "netop1"
}
```
It will return a `connection_id`: `16453564131388984820`.

Click `Try it out` for `/v1/transaction`, and execute the following query
```
{
  "connection_id": "16453564131388984820",
  "type": "QUERY",
  "chaincode_id": "mycc",
  "transaction": "query",
  "parameter": [
    "a"
  ]
}
```
It will return the current state of `a` on the sample Fabric channel, e.g. `90`.

Click `Try it out` for `/v1/transaction` again, and execute the following transaction to reduce the value of `a` by `10`
```
{
  "connection_id": "16453564131388984820",
  "type": "INVOKE",
  "chaincode_id": "mycc",
  "transaction": "invoke",
  "parameter": [
    "a","b","10"
  ]
}
```
Execute the above query again, it should return a reduced value of `a`, e.g., `80`.

Note that this gateway service can be used to test any instantiated chaincode, and it supports connections to multiple channels or networks, as long as the connection is configured by using the script `./gateway.sh config [options]`.  You can also use a gRPC client to send API requests to the gateway service.

## TODO
* Support HTTPS and gRPCs for secure client connections.
* Demonstrate gRPCs client app.