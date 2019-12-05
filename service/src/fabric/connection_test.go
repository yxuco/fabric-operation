/*
 * Copyright © 2018. TIBCO Software Inc.
 * This file is subject to the license terms contained
 * in the license file that is distributed with this file.
 */
package fabric

import (
	"fmt"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const (
	connectorName = "test"
	configFile    = "${PWD}/../../config/config_min.yaml"
	matcherFile   = "${PWD}/../../config/local_entity_matchers.yaml"
	channelID     = "mychannel"
	org           = "org1"
	user          = "User1"
	ccID          = "mycc"
)

func TestClient(t *testing.T) {
	_, err := ReadFile(configFile)
	require.NoError(t, err, "failed to read config file %s", configFile)

	_, err = ReadFile(matcherFile)
	require.NoError(t, err, "failed to read entity matcher file %s", matcherFile)

	fbClient, err := NewNetworkClient(configFile, matcherFile, channelID, user, org)
	require.NoError(t, err, "failed to create fabric client %s", connectorName)
	fmt.Printf("created fabric client %+v\n", fbClient)

	// query original
	result, _, err := fbClient.QueryChaincode(ccID, "query", [][]byte{[]byte("a")}, nil, 0, nil)
	require.NoError(t, err, "failed to query %s", ccID)
	fmt.Printf("Query result: %s\n", string(result))
	origValue := result

	// update
	result, _, err = fbClient.ExecuteChaincode(ccID, "invoke", [][]byte{[]byte("a"), []byte("b"), []byte("10")}, nil, 0, nil)
	require.NoError(t, err, "failed to invoke %s", ccID)
	fmt.Printf("Invoke result: %s\n", string(result))

	// query after update
	result, _, err = fbClient.QueryChaincode(ccID, "query", [][]byte{[]byte("a")}, nil, 0, nil)
	require.NoError(t, err, "failed to query %s", ccID)
	fmt.Printf("Query result: %s\n", string(result))
	assert.NotEqual(t, origValue, result, "original %s should different from %s", string(origValue), string(result))
}
