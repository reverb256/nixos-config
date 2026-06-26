{ writeShellScriptBin, coreutils, jq, curl }:
writeShellScriptBin "kokoro-tts.sh" ''
  set -euo pipefail
  INPUT_FILE="$1"
  OUTPUT_FILE="$2"
  VOICE="''${3:-af_bella}"
  API="http://nexus.lan:8880/v1/audio/speech"
  TEXT=$(${coreutils}/bin/cat "$INPUT_FILE")
  PAYLOAD=$(${jq}/bin/jq -n \
    --arg model "kokoro" \
    --arg input "$TEXT" \
    --arg voice "$VOICE" \
    '{model: $model, input: $input, voice: $voice}')
  ${curl}/bin/curl -s -X POST "$API" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    -o "$OUTPUT_FILE"
''
