# Network utility

This utility is a CLI script for Hyperledger Fabric network operations. It currently supports the following commands:
* Start a Hyperledger Fabric network;
* Shutdown a Hyperledger Fabric network;
* Run smoke test to verify the network health;
* Scale up number of peer nodes while a network is running;
* Scale up orderer nodes while a network is running;
* Create new channels;
* Make a peer node join a channel;
* Package and sign chaincode in cds format;
* Install new chaincodes on a peer node;
* Instantiate new chaincode on a specified channel;
* Upgrade a chaincode on a specified channel;
* Execute queries on a specified chaincode;
* Invoke transactions on a specifiedd chaincode;
* Create channel update for adding a new peer organization;
* Create channel update for adding a new orderer to RAFT consensus;
* Sign a transaction for channel update;
* Update channel config.

More operations will be added in the future to support operations of fabric network that spans multiple organizations and multiple cloud providers.

Following is the current usage info of this utility:
```
./network.sh -h

Usage:
  network.sh <cmd> [-p <property file>] [-t <env type>] [-d]
    <cmd> - one of the following commands:
      - 'start' - start orderers and peers of the fabric network
      - 'shutdown' - shutdown orderers and peers of the fabric network
      - 'test' - run smoke test
      - 'scale-peer' - scale up peer nodes with argument '-r <replicas>'
      - 'scale-orderer' - scale up orderer nodes (RAFT consenter only one at a time)
      - 'create-channel' - create a channel using peer-0, with argument '-c <channel>'
      - 'join-channel' - join a peer to a channel with arguments: -n <peer> -c <channel> [-a]
        e.g., network.sh join-channel -n peer-0 -c mychannel -a
      - 'package-chaincode' - package chaincode on a peer with arguments: -n <peer> -f <folder> -s <name> [-v <version>] [-g <lang>] [-e <policy>]
        e.g., network.sh package-chaincode -n peer-0 -f chaincode_example02/go -s mycc -v 1.0 -g golang -e "OR ('netop1MSP.admin')"
      - 'sign-chaincode' - sign chaincode package on a peer with arguments: -n <peer> -f <cds-file>
        e.g., network.sh sign-chaincode -n peer-0 -f mycc_1.0.cds
      - 'install-chaincode' - install chaincode on a peer with arguments: -n <peer> -f <cds-file>
        e.g., network.sh install-chaincode -n peer-0 -f mycc_1.0.cds
      - 'instantiate-chaincode' - instantiate chaincode on a peer, with arguments: -n <peer> -c <channel> -s <name> [-v <version>] [-m <args>] [-e <policy>] [-g <lang>]
        e.g., network.sh instantiate-chaincode -n peer-0 -c mychannel -s mycc -v 1.0 -m '{"Args":["init","a","100","b","200"]}'
      - 'upgrade-chaincode' - upgrade chaincode on a peer, with arguments: -n <peer> -c <channel> -s <name> -v <version> [-m <args>] [-e <policy>] [-g <lang>]
        e.g., network.sh upgrade-chaincode -n peer-0 -c mychannel -s mycc -v 2.0 -m '{"Args":["init","a","100","b","200"]}'
      - 'query-chaincode' - query chaincode from a peer, with arguments: -n <peer> -c <channel> -s <name> -m <args>
        e.g., network.sh query-chaincode -n peer-0 -c mychannel -s mycc -m '{"Args":["query","a"]}'
      - 'invoke-chaincode' - invoke chaincode from a peer, with arguments: -n <peer> -c <channel> -s <name> -m <args>
        e.g., network.sh invoke-chaincode -n peer-0 -c mychannel -s mycc -m '{"Args":["invoke","a","b","10"]}'
      - 'add-org-tx' - generate update tx for add new msp to a channel, with arguments: -o <msp> -c <channel>
        e.g., network.sh add-org-tx -o peerorg1MSP -c mychannel
      - 'add-orderer-tx' - generate update tx for add new orderers to a channel (default system-channel) for RAFT consensus, with argument: -f <consenter-file> [-c <channel>]
        e.g., network.sh add-orderer-tx -f ordererConfig-3.json
      - 'sign-transaction' - sign a config update transaction file in the CLI working directory, with argument = -f <tx-file>
        e.g., network.sh sign-transaction -f "mychannel-peerorg1MSP.pb"
      - 'update-channel' - send transaction to update a channel, with arguments ('-a' means orderer user): -f <tx-file> -c <channel> [-a]
        e.g., network.sh update-channel -f "mychannel-peerorg1MSP.pb" -c mychannel
    -p <property file> - the .env file in config folder that defines network properties, e.g., netop1 (default)
    -t <env type> - deployment environment type: one of 'docker', 'k8s' (default), 'aws', or 'az'
    -d - delete ledger data when shutdown network
    -r <replicas> - new peer node replica count for scale-peer
    -n <peer> - peer ID for channel/chaincode commands
    -c <channel> - channel ID for channel/chaincode commands
    -a - update anchor for join-channel, or copy new chaincode for install-chaincode
    -f <cc folder> - chaincode folder name, or config transaction file
    -s <cc name> - chaincode name
    -v <cc version> - chaincode version
    -g <cc language> - chaincode language, default 'golang'
    -m <args> - args for chaincode commands
    -e <policy> - endorsement policy for instantiate/upgrade chaincode, e.g., "OR ('Org1MSP.peer')"
    -o <org msp> - org msp to be added to a channel
  network.sh -h (print this message)
  ```