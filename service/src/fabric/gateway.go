// Package fabric implements gateway service to connect to a fabric network and invoke/query a chaincode.
package fabric

import (
	"context"
	"encoding/json"

	"github.com/golang/glog"
	"github.com/pkg/errors"
)

var defaultConfig ConnectionData

// SetConfig caches default config parameters
func SetConfig(configPath, patternPath, channel, user, org string) {
	defaultConfig = ConnectionData{
		ChannelId:      channel,
		UserName:       user,
		OrgName:        org,
		NetworkConfig:  configPath,
		PattenMatchers: patternPath,
	}
}

// Service implements audit.AuditServiceServer interface
type Service struct {
}

// Connect creates a Fabric connection, or finds a cached connection matching the channel and user/org.
func (*Service) Connect(ctx context.Context, req *ConnectionRequest) (*ConnectionResponse, error) {
	data := req.GetData()
	networkConfig := data.GetNetworkConfig()
	patternMatchers := data.GetPattenMatchers()
	if networkConfig == "" {
		networkConfig = defaultConfig.NetworkConfig
		if patternMatchers == "" {
			patternMatchers = defaultConfig.PattenMatchers
		}
	}
	channelID := data.GetChannelId()
	if channelID == "" {
		channelID = defaultConfig.ChannelId
	}
	userName := data.GetUserName()
	if userName == "" {
		userName = defaultConfig.UserName
	}
	orgName := data.GetOrgName()
	if orgName == "" {
		orgName = defaultConfig.OrgName
	}

	client, err := NewNetworkClient(networkConfig, patternMatchers, channelID, userName, orgName)
	if err != nil {
		glog.Errorf("Failed Fabric connection for channel %s: %+v", channelID, err)
		return nil, err
	}
	glog.V(2).Infof("Return fabric connection id %d", client.cid)
	return &ConnectionResponse{
		Code:         200,
		ConnectionId: client.cid,
	}, nil
}

// Execute invokes a chaincode transaction or query chaincode.
func (*Service) Execute(ctx context.Context, req *TransactionRequest) (*TransactionResponse, error) {
	data := req.GetData()
	cid := data.GetConnectionId()
	if cid == 0 {
		return nil, errors.New("connection id is not specified")
	}
	fbClient, ok := clientMap[cid]
	if !ok {
		return nil, errors.Errorf("No Fabric connection found for id %d", cid)
	}
	var args [][]byte
	if params := data.GetParameter(); params != nil {
		for _, p := range params {
			args = append(args, []byte(p))
		}
	}
	var transMap map[string][]byte
	transient := data.GetTransientMap()
	if transient != "" {
		var value map[string]interface{}
		if err := json.Unmarshal([]byte(transient), &value); err != nil {
			glog.Warningf("Failed to parse transient map: %s\n error: %+v", transient, err)
		} else {
			transMap = make(map[string][]byte)
			for k, v := range value {
				if jsonBytes, err := json.Marshal(v); err != nil {
					glog.V(1).Infof("Failed to marshal transient data %+v\n error: %+v", v, err)
				} else {
					transMap[k] = jsonBytes
				}
			}
		}
	}

	if data.GetType() == TransactionType_INVOKE {
		// invoke
		result, _, err := fbClient.ExecuteChaincode(
			data.GetChaincodeId(), data.GetTransaction(), args, transMap,
			data.GetTimeout(), data.GetEndpoint())
		if err != nil {
			glog.Errorf("Failed to invoke chaincode %s: %+v", data.GetChaincodeId(), err)
			return nil, err
		}
		glog.V(2).Infof("Result of chaincode %s for transaction %s: %s", data.GetChaincodeId(), data.GetTransaction(), string(result))
		return &TransactionResponse{
			Code: 200,
			Data: string(result),
		}, nil
	}

	// query
	result, _, err := fbClient.QueryChaincode(
		data.GetChaincodeId(), data.GetTransaction(), args, transMap,
		data.GetTimeout(), data.GetEndpoint())
	if err != nil {
		glog.Errorf("Failed to query chaincode %s: %+v", data.GetChaincodeId(), err)
		return nil, err
	}
	glog.V(2).Infof("Result of chaincode %s for transaction %s: %s", data.GetChaincodeId(), data.GetTransaction(), string(result))
	return &TransactionResponse{
		Code: 200,
		Data: string(result),
	}, nil
}
