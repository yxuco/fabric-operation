package fabric

import (
	"bytes"
	"fmt"
	"os"
	"strings"
	"time"

	"hash/fnv"
	"path/filepath"

	"github.com/golang/glog"
	"github.com/pkg/errors"

	"github.com/hyperledger/fabric-sdk-go/pkg/client/channel"
	"github.com/hyperledger/fabric-sdk-go/pkg/common/errors/retry"
	"github.com/hyperledger/fabric-sdk-go/pkg/common/providers/core"
	"github.com/hyperledger/fabric-sdk-go/pkg/common/providers/fab"
	"github.com/hyperledger/fabric-sdk-go/pkg/core/config"
	"github.com/hyperledger/fabric-sdk-go/pkg/fabsdk"
)

const (
	configType = "yaml"
)

// cached Fabric client connections
var clientMap = map[uint64]*NetworkClient{}

// NetworkClient holds fabric client pointers for chaincode invocations.
type NetworkClient struct {
	cid    uint64
	sdk    *fabsdk.FabricSDK
	client *channel.Client
}

// NewNetworkClient returns a new or cached fabric client
func NewNetworkClient(configPath, patternPath, channelID, user, org string) (*NetworkClient, error) {
	clientKey := fmt.Sprintf("%s.%s.%s", channelID, user, org)
	hash := HashCode(clientKey)
	if fbClient, ok := clientMap[hash]; ok && fbClient != nil {
		glog.V(2).Infof("found cached fabric connection: %s", clientKey)
		return fbClient, nil
	}

	glog.V(2).Infof("Creating new fabric connection: %s", clientKey)
	provider, err := networkConfigProvider(configPath, patternPath)
	if err != nil {
		return nil, errors.Wrap(err, "Failed to create config provider")
	}
	sdk, err := fabsdk.New(provider)
	if err != nil {
		return nil, errors.Wrapf(err, "Failed to create new SDK")
	}

	glog.V(2).Infof("connect to fabric with user: %s", user)
	opts := []fabsdk.ContextOption{fabsdk.WithUser(user)}
	if org != "" {
		glog.V(2).Infof("connect to fabric with org: %s", org)
		opts = append(opts, fabsdk.WithOrg(org))
	}
	glog.V(2).Infof("connect to fabric channel: %s", channelID)
	client, err := channel.New(sdk.ChannelContext(channelID, opts...))
	if err != nil {
		return nil, errors.Wrapf(err, "Failed to create new client of channel %s", channelID)
	}
	glog.V(2).Info("created new channel client")
	fbClient := &NetworkClient{
		cid:    hash,
		sdk:    sdk,
		client: client,
	}
	clientMap[hash] = fbClient

	return fbClient, nil
}

func networkConfigProvider(configPath, patternPath string) (core.ConfigProvider, error) {
	glog.V(2).Infof("read network file: %s and pattern matcher file: %s", configPath, patternPath)
	netConfig, err := ReadFile(configPath)
	if err != nil {
		return nil, errors.Wrapf(err, "Failed to read network config %s", configPath)
	}
	configProvider := config.FromRaw(netConfig, configType)

	override, err := ReadFile(patternPath)
	if err != nil {
		glog.Errorf("Failed to read pattern matcher file %s: %+v", patternPath, err)
		return configProvider, nil
	}
	if override != nil {
		return func() ([]core.ConfigBackend, error) {
			matcherProvider := config.FromRaw(override, configType)
			matcherBackends, err := matcherProvider()
			if err != nil {
				glog.Errorf("failed to parse entity matchers: %+v", err)
				// return the original config provider defined by configPath
				return configProvider()
			}

			currentBackends, err := configProvider()
			if err != nil {
				glog.Errorf("failed to parse network config: %+v", err)
				return nil, err
			}

			// return the combined config with matcher precedency
			return append(matcherBackends, currentBackends...), nil
		}, nil
	}
	glog.V(2).Info("No pattern matcher override is used")
	return configProvider, nil
}

// Close closes Fabric client connection
func (c *NetworkClient) Close() {
	c.sdk.Close()
}

// QueryChaincode sends query request to Fabric network
func (c *NetworkClient) QueryChaincode(ccID, fcn string, args [][]byte, transient map[string][]byte, timeout int64, endpoints []string) ([]byte, int32, error) {
	opts := []channel.RequestOption{channel.WithRetry(retry.DefaultChannelOpts)}
	if timeout > 0 {
		opts = append(opts, channel.WithTimeout(fab.Query, time.Duration(timeout)*time.Millisecond))
	}
	if endpoints != nil && len(endpoints) > 0 {
		opts = append(opts, channel.WithTargetEndpoints(endpoints...))
	}
	response, err := c.client.Query(channel.Request{ChaincodeID: ccID, Fcn: fcn, Args: args, TransientMap: transient}, opts...)
	if err != nil {
		return nil, 500, err
	}
	return response.Payload, response.ChaincodeStatus, nil
}

// ExecuteChaincode sends invocation request to Fabric network
func (c *NetworkClient) ExecuteChaincode(ccID, fcn string, args [][]byte, transient map[string][]byte, timeout int64, endpoints []string) ([]byte, int32, error) {
	opts := []channel.RequestOption{channel.WithRetry(retry.DefaultChannelOpts)}
	if timeout > 0 {
		opts = append(opts, channel.WithTimeout(fab.Execute, time.Duration(timeout)*time.Millisecond))
	}
	if endpoints != nil && len(endpoints) > 0 {
		opts = append(opts, channel.WithTargetEndpoints(endpoints...))
	}
	response, err := c.client.Execute(channel.Request{ChaincodeID: ccID, Fcn: fcn, Args: args, TransientMap: transient}, opts...)
	if err != nil {
		return nil, 500, err
	}
	return response.Payload, response.ChaincodeStatus, nil
}

// HashCode calcullates hash code of specified text
func HashCode(text string) uint64 {
	algorithm := fnv.New64a()
	algorithm.Write([]byte(text))
	return algorithm.Sum64()
}

// ReadFile returns content of a specified file
func ReadFile(pathName string) ([]byte, error) {
	if pathName == "" {
		glog.V(2).Info("file not specified")
		return nil, nil
	}
	filename := pathName
	// get absolute file path using env ${CONFIG_PATH}
	if !filepath.IsAbs(filename) {
		dir, ok := os.LookupEnv("CONFIG_PATH")
		if !ok {
			// default to 'config' folder under current working directory
			dir = "./config"
		}
		filename = filepath.Join(dir, filename)
	}
	f, err := os.Open(Subst(filename))
	if err != nil {
		return nil, errors.Wrapf(err, "Failed to open file: %s", filename)
	}
	defer f.Close()
	fi, err := f.Stat()
	if err != nil {
		return nil, errors.Wrapf(err, "Failed to read file stat: %s", filename)
	}
	s := fi.Size()
	cBytes := make([]byte, s)
	n, err := f.Read(cBytes)
	if err != nil {
		return nil, errors.Wrapf(err, "Failed to read file: %s", filename)
	}
	if n == 0 {
		glog.Infof("file %s is empty", filename)
		return nil, nil
	}
	return cBytes, err
}

// Subst replaces instances of '${VARNAME}' (eg ${GOPATH}) with the variable.
// Variables names that are not set by the SDK are replaced with the environment variable.
func Subst(path string) string {
	const (
		sepPrefix = "${"
		sepSuffix = "}"
	)

	splits := strings.Split(path, sepPrefix)

	var buffer bytes.Buffer

	// first split precedes the first sepPrefix so should always be written
	buffer.WriteString(splits[0]) // nolint: gas

	for _, s := range splits[1:] {
		subst, rest := substVar(s, sepPrefix, sepSuffix)
		buffer.WriteString(subst) // nolint: gas
		buffer.WriteString(rest)  // nolint: gas
	}

	return buffer.String()
}

// substVar searches for an instance of a variables name and replaces them with their value.
// The first return value is substituted portion of the string or noMatch if no replacement occurred.
// The second return value is the unconsumed portion of s.
func substVar(s string, noMatch string, sep string) (string, string) {
	endPos := strings.Index(s, sep)
	if endPos == -1 {
		return noMatch, s
	}

	v, ok := os.LookupEnv(s[:endPos])
	if !ok {
		return noMatch, s
	}
	return v, s[endPos+1:]
}
