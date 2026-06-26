{ writeShellScriptBin, jq, curl }:
writeShellScriptBin "chatterbox-tts.sh" ''
  set -euo pipefail
  INPUT_FILE="$1"
  OUTPUT_FILE="$2"
  VOICE="''${3:-Connor.wav}"
  API="http://localhost:8004/tts"

  TEXT=$(${jq}/bin/jq -Rs '{text: ., voice_mode: "predefined", predefined_voice_id: $voice, output_format: "mp3", split_text: false}' \
    --arg voice "$VOICE" < "$INPUT_FILE")

  ${curl}/bin/curl -s -X POST "$API" \
    -H "Content-Type: application/json" \
    -d "$TEXT" \
    -o "$OUTPUT_FILE"
''
