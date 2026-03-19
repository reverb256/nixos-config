package main

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"

	"github.com/btcsuite/btcd/btcec/v2"
)

func main() {
	hexKey := "63836ebc5d3eeb88ba2105daf61190640b17fb5943fab1da280ff0bcbcc43e62"
	expectedAddr := "akash1s97zjxzn3tnudawjhjhpus9x7yn6dgukzar372"

	privBytes, err := hex.DecodeString(hexKey)
	if err != nil {
		log.Fatal(err)
	}

	// Get public key using secp256k1
	privKey, _ := btcec.PrivKeyFromBytes(privBytes)
	pubKey := privKey.PubKey().SerializeCompressed()

	// Remove compression prefix (0x02 or 0x03) to get raw 32-byte pubkey
	pubKeyRaw := pubKey[1:]

	// Cosmos SDK keyring test backend format
	type PubKey struct {
		Type string `json:"@type"`
		Key  string `json:"key"`
	}
	type PrivKey struct {
		Type string `json:"@type"`
		Key  string `json:"key"`
	}
	type KeyringEntry struct {
		Name     string  `json:"name"`
		Type     string  `json:"type"`
		Address  string  `json:"address"`
		PubKey   PubKey  `json:"pubkey"`
		PrivKey  PrivKey `json:"privkey"`
	}

	entry := KeyringEntry{
		Name:    "provider-wallet",
		Type:    "cosmos-sdk/Secp256k1",
		Address: expectedAddr,
		PubKey: PubKey{
			Type: "/cosmos.crypto.secp256k1.PubKey",
			Key:  base64.StdEncoding.EncodeToString(pubKeyRaw),
		},
		PrivKey: PrivKey{
			Type: "/cosmos.crypto.secp256k1.PrivKey",
			Key:  base64.StdEncoding.EncodeToString(privBytes),
		},
	}

	jsonBytes, _ := json.MarshalIndent(entry, "", "  ")
	fmt.Println("Keyring file (provider-wallet.info):")
	fmt.Println(string(jsonBytes))

	// Also derive address to verify
	sha := sha256.Sum256(pubKeyRaw)
	sha2 := sha256.Sum256(sha[:])
	fmt.Printf("\nDerived address (first 20 bytes of double SHA256):\n%x\n", sha2[:20])
	fmt.Printf("Expected: %s\n", expectedAddr)
}
