# Akash Provider Key Information

**Created:** 2026-03-18

## Provider Address
`akash1ykpetck92tqyqdkd3ra2c3spezct9tntyuef85`

## Mnemonic (BIP39 Seed Phrase)
```
famous equal path apple wet alpha stable one wall left endless figure brass ancient jar butter gallery erupt health hotel seven urge caution bright
```

⚠️ **IMPORTANT**: Store this mnemonic securely! It is the ONLY way to recover this wallet.

## Key Import Method
The key is successfully imported using:
```bash
echo "MNEMONIC" | provider-services keys add provider-wallet --keyring-backend=test --recover
```

## Status
- ✅ Init container successfully imports the key
- ✅ Keyring is properly configured
- ⚠️ Main container exits with code 1 - needs further investigation

## Notes
- Original hex key address: `akash1s97zjxzn3tnudawjhjhpus9x7yn6dgukzar372`
- Original hex key: `63836ebc5d3eeb88ba2105daf61190640b17fb5943fab1da280ff0bcbcc43e62`
- The provider-services CLI does NOT have a direct hex import command
- `keys import` expects ASCII-armored key files (PEM format) but exact format is unclear
- Using mnemonic with `--recover` is the reliable method

## Next Steps
1. Fix main container startup issue (likely missing config.toml)
2. Verify provider can connect to blockchain
3. Register provider on-chain
4. Configure bid pricing and attributes
