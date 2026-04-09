#!/usr/bin/env bash
#
# Create a standalone llamafile with embedded model
# Combines llamafile binary with GGUF model weights into a single executable
#
# Usage:
#   ./create-llamafile.sh <model-path> <output-name> [additional-args]
#
# Example:
#   ./create-llamafile.sh \
#     ~/.lmstudio/models/mradermacher/Qwen3.5-9B-Unredacted-MAX-i1-GGUF/Qwen3.5-9B-Unredacted-MAX.i1-Q4_K_S.gguf \
#     qwen-9b-unredacted.llamafile \
#     --host 0.0.0.0 --port 8081

set -euo pipefail

# Configuration
LLAMAFILE_VERSION="${LLAMAFILE_VERSION:-0.8.17}"
LLAMAFILE_URL="https://github.com/Mozilla-Ocho/llamafile/releases/download/${LLAMAFILE_VERSION}/llamafile-${LLAMAFILE_VERSION}"
OUTPUT_DIR="${OUTPUT_DIR:-/etc/nixos/llamafiles}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
    echo -e "${RED}✗${NC} $*"
    exit 1
}

# Parse arguments
if [ $# -lt 2 ]; then
    log_error "Usage: $0 <model-path> <output-name> [additional-args]"
    echo ""
    echo "Example:"
    echo "  $0 \\"
    echo "    ~/.lmstudio/models/mradermacher/Qwen3.5-9B-Unredacted-MAX-i1-GGUF/Qwen3.5-9B-Unredacted-MAX.i1-Q4_K_S.gguf \\"
    echo "    qwen-9b-unredacted.llamafile \\"
    echo "    --host 0.0.0.0 --port 8081"
    echo ""
    echo "Model path must be a GGUF file."
    exit 1
fi

MODEL_PATH="$1"
OUTPUT_NAME="$2"
shift 2
ADDITIONAL_ARGS=("$@")

# Validate model path
if [ ! -f "$MODEL_PATH" ]; then
    log_error "Model file not found: $MODEL_PATH"
fi

# Check if it's a GGUF file
if [[ ! "$MODEL_PATH" =~ \.gguf$ ]]; then
    log_warn "Model doesn't have .gguf extension: $MODEL_PATH"
fi

MODEL_SIZE=$(du -h "$MODEL_PATH" | cut -f1)
MODEL_NAME=$(basename "$MODEL_PATH" .gguf)

log_info "Creating llamafile for: $MODEL_NAME"
log_info "Model size: $MODEL_SIZE"

# Create output directory
mkdir -p "$OUTPUT_DIR"
OUTPUT_PATH="$OUTPUT_DIR/$OUTPUT_NAME"

# Download llamafile binary if not cached
LLAMAFILE_BIN="$OUTPUT_DIR/llamafile-${LLAMAFILE_VERSION}"
if [ ! -f "$LLAMAFILE_BIN" ]; then
    log_info "Downloading llamafile ${LLAMAFILE_VERSION}..."
    curl -L -o "$LLAMAFILE_BIN" "$LLAMAFILE_URL"
    chmod +x "$LLAMAFILE_BIN"
    log_success "Downloaded llamafile binary"
else
    log_info "Using cached llamafile binary"
fi

# Create .args file for default arguments
ARGS_FILE=$(mktemp)
cat > "$ARGS_FILE" <<EOF
-m
$(basename "$MODEL_PATH")
--server
--v2
--host
127.0.0.1
--port
8081
-ngl
999
-c
8192
-t
8
--batch-size
512
--ubatch-size
512
EOF

# Add additional args
for arg in "${ADDITIONAL_ARGS[@]}"; do
    echo "$arg" >> "$ARGS_FILE"
done

# Add placeholder for user arguments
echo "..." >> "$ARGS_FILE"

log_info "Building llamafile with embedded model..."

# Copy llamafile as base
cp "$LLAMAFILE_BIN" "$OUTPUT_PATH"
chmod +x "$OUTPUT_PATH"

# Use zipalign to embed the model and args
# This requires the zipalign tool from llamafile
log_info "Embedding model and default arguments..."

# Check if zipalign exists
if command -v zipalign &>/dev/null; then
    zipalign -j0 \
        "$OUTPUT_PATH" \
        "$MODEL_PATH" \
        "$ARGS_FILE"
    rm "$ARGS_FILE"
    log_success "Embedded model and arguments"
else
    log_warn "zipalign not found - creating external model config"
    rm "$ARGS_FILE"

    # Create a wrapper script instead
    cat > "${OUTPUT_PATH}.sh" <<EOF
#!/bin/bash
# Llamafile wrapper for $MODEL_NAME
SCRIPT_DIR="\$(cd "\$(dirname "\$0")" && pwd)"
MODEL_PATH="\$SCRIPT_DIR/$(basename "$MODEL_PATH")"

exec "$OUTPUT_PATH" \
  -m "\$MODEL_PATH" \
  --server --v2 \
  --host 127.0.0.1 --port 8081 \
  -ngl 999 \
  -c 8192 \
  -t 8 \
  ${ADDITIONAL_ARGS[*]:-} \
  "\$@"
EOF
    chmod +x "${OUTPUT_PATH}.sh"
    log_info "Created wrapper script: ${OUTPUT_PATH}.sh"
fi

# Get final size
FINAL_SIZE=$(du -h "$OUTPUT_PATH" | cut -f1)

log_success "Created llamafile: $OUTPUT_PATH ($FINAL_SIZE)"
echo ""
echo "To run:"
echo "  ./$OUTPUT_NAME"
if [ -f "${OUTPUT_PATH}.sh" ]; then
    echo "  or: ./${OUTPUT_NAME}.sh"
fi
echo ""
echo "To enable as systemd service:"
echo "  services.llamafile = {"
echo "    enable = true;"
echo "    modelPath = \"$MODEL_PATH\";"
echo "  };"
