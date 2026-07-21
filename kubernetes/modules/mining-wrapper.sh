#!/bin/sh
# Mining wrapper for profit switching.
# Reads the best coin from ConfigMap (mounted at /etc/mining-config/)
# and runs the appropriate miner with correct args.
# Watches for config changes and switches miners without pod restart.

set -e

CONFIG_DIR="${CONFIG_DIR:-/etc/mining-config}"
GROUP="${MINING_GROUP:-nvidia}"
WALLET="${WALLET:-krxXVNVMM7}"
MINERS_DIR="/opt/miners"
POLL_INTERVAL=60
MINER_PID=""

# Kryptex pool configs
get_pool_args() {
    coin="$1"
    worker="$2"
    case "$coin" in
        rvn)
            RIGEL=$(find "$MINERS_DIR" -name rigel -type f 2>/dev/null | head -1)
            [ -n "$RIGEL" ] && echo "exec $RIGEL -a kawpow --coin rvn -o stratum+ssl://rvn-us.kryptex.network:8031 -u ${WALLET}.${worker} -p x -w ${worker} -d ${DEVICE_INDEX:-0} --api-bind 0.0.0.0:${API_PORT:-4068}"
            ;;
        cfx)
            RIGEL=$(find "$MINERS_DIR" -name rigel -type f 2>/dev/null | head -1)
            [ -n "$RIGEL" ] && echo "exec $RIGEL -a octopus --coin cfx -o stratum+ssl://cfx-us.kryptex.network:8027 -u ${WALLET}.${worker} -p x -w ${worker} -d ${DEVICE_INDEX:-0} --api-bind 0.0.0.0:${API_PORT:-4068}"
            ;;
        erg)
            RIGEL=$(find "$MINERS_DIR" -name rigel -type f 2>/dev/null | head -1)
            [ -n "$RIGEL" ] && echo "exec $RIGEL -a autolykos2 -o stratum+tcp://erg-us.kryptex.network:7021 -u ${WALLET}.${worker} -p x -w ${worker} -d ${DEVICE_INDEX:-0} --api-bind 0.0.0.0:${API_PORT:-4068}"
            ;;
        nexa)
            RIGEL=$(find "$MINERS_DIR" -name rigel -type f 2>/dev/null | head -1)
            [ -n "$RIGEL" ] && echo "exec $RIGEL -a nexapow -o stratum+tcp://nexa-us.kryptex.network:7026 -u ${WALLET}.${worker} -p x -w ${worker} -d ${DEVICE_INDEX:-0} --api-bind 0.0.0.0:${API_PORT:-4068}"
            ;;
        xna)
            RIGEL=$(find "$MINERS_DIR" -name rigel -type f 2>/dev/null | head -1)
            [ -n "$RIGEL" ] && echo "exec $RIGEL -a kawpow --coin xna -o stratum+tcp://xna-us.kryptex.network:7024 -u ${WALLET}.${worker} -p x -w ${worker} -d ${DEVICE_INDEX:-0} --api-bind 0.0.0.0:${API_PORT:-4068}"
            ;;
        iron)
            RIGEL=$(find "$MINERS_DIR" -name rigel -type f 2>/dev/null | head -1)
            [ -n "$RIGEL" ] && echo "exec $RIGEL -a fishhash -o stratum+tcp://iron-us.kryptex.network:7050 -u ${WALLET}.${worker} -p x -w ${worker} -d ${DEVICE_INDEX:-0} --api-bind 0.0.0.0:${API_PORT:-4068}"
            ;;
        xel)
            RIGEL=$(find "$MINERS_DIR" -name rigel -type f 2>/dev/null | head -1)
            [ -n "$RIGEL" ] && echo "exec $RIGEL -a xelishashv3 -o stratum+tcp://xel-us.kryptex.network:7055 -u ${WALLET}.${worker} -p x -w ${worker} -d ${DEVICE_INDEX:-0} --api-bind 0.0.0.0:${API_PORT:-4068}"
            ;;
        xtm)
            RIGEL=$(find "$MINERS_DIR" -name rigel -type f 2>/dev/null | head -1)
            [ -n "$RIGEL" ] && echo "exec $RIGEL -a sha3x --coin xtm -o stratum+ssl://xtm-c29.kryptex.network:8040 -u ${WALLET}.${worker} -p x -w ${worker} -d ${DEVICE_INDEX:-0} --api-bind 0.0.0.0:${API_PORT:-4068}"
            ;;
        *)
            echo "# Unknown coin: $coin" >&2
            ;;
    esac
}

get_trm_pool_args() {
    coin="$1"
    worker="$2"
    case "$coin" in
        rvn)
            TRM="/bin/teamredminer"
            [ -x "$TRM" ] && echo "exec $TRM -a kawpow -o stratum+ssl://rvn-us.kryptex.network:8031 -u ${WALLET}.${worker} -p x --api_listen=0.0.0.0:${API_PORT:-4070} -d ${DEVICE_INDEX:-0}"
            ;;
        xna)
            TRM="/bin/teamredminer"
            [ -x "$TRM" ] && echo "exec $TRM -a kawpow -o stratum+tcp://xna-us.kryptex.network:7024 -u ${WALLET}.${worker} -p x --api_listen=0.0.0.0:${API_PORT:-4070} -d ${DEVICE_INDEX:-0}"
            ;;
        erg)
            TRM="/bin/teamredminer"
            [ -x "$TRM" ] && echo "exec $TRM -a autolykos2 -o stratum+tcp://erg-us.kryptex.network:7021 -u ${WALLET}.${worker} -p x --api_listen=0.0.0.0:${API_PORT:-4070} -d ${DEVICE_INDEX:-0}"
            ;;
        *)
            echo "# AMD incompatible coin: $coin" >&2
            ;;
    esac
}

get_current_coin() {
    if [ -f "${CONFIG_DIR}/${GROUP}-best" ]; then
        cat "${CONFIG_DIR}/${GROUP}-best"
    else
        echo ""
    fi
}

tune_gpu() {
    algo="$1"
    TUNE_SCRIPT="/opt/wrapper/gpu-tune.sh"
    if [ -f "$TUNE_SCRIPT" ]; then
        echo "[wrapper] Applying GPU tuning for algo=$algo"
        sh "$TUNE_SCRIPT" "$algo" 2>&1 || echo "[wrapper] GPU tuning failed, continuing"
    else
        echo "[wrapper] No tuning script found, skipping"
    fi
}

start_miner() {
    coin="$1"
    echo "[wrapper] Starting miner for ${coin} (group=${GROUP})"

    case "$coin" in
        rvn|xna)  ALGO="kawpow" ;;
        cfx)      ALGO="octopus" ;;
        erg)      ALGO="autolykos2" ;;
        nexa)     ALGO="nexapow" ;;
        iron)     ALGO="fishhash" ;;
        xel)      ALGO="xelishashv3" ;;
        xtm)      ALGO="sha3x" ;;
        *)        ALGO="kawpow" ;;
    esac
    tune_gpu "$ALGO"

    if [ "$MINER_TYPE" = "teamredminer" ]; then
        cmd=$(get_trm_pool_args "$coin" "$WORKER_NAME")
    else
        cmd=$(get_pool_args "$coin" "$WORKER_NAME")
    fi

    if [ -z "$cmd" ] || echo "$cmd" | grep -q "^# "; then
        echo "[wrapper] No compatible miner for ${coin}, falling back to ${DEFAULT_COIN:-xtm}"
        if [ "$MINER_TYPE" = "teamredminer" ]; then
            cmd=$(get_trm_pool_args "${DEFAULT_COIN:-xtm}" "$WORKER_NAME")
        else
            cmd=$(get_pool_args "${DEFAULT_COIN:-xtm}" "$WORKER_NAME")
        fi
    fi

    echo "[wrapper] Command: $cmd"
    eval "$cmd" &
    MINER_PID=$!
}

stop_miner() {
    if [ -n "$MINER_PID" ] && kill -0 "$MINER_PID" 2>/dev/null; then
        echo "[wrapper] Stopping miner (PID=$MINER_PID)"
        kill -TERM "$MINER_PID" 2>/dev/null || true
        for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
            kill -0 "$MINER_PID" 2>/dev/null || break
            sleep 1
        done
        kill -0 "$MINER_PID" 2>/dev/null && kill -KILL "$MINER_PID" 2>/dev/null || true
        wait "$MINER_PID" 2>/dev/null || true
        MINER_PID=""
    fi
}

# --- Main loop ---

if [ -d "$MINERS_DIR" ] && [ "$(ls -A "$MINERS_DIR" 2>/dev/null)" ]; then
    echo "[wrapper] Miners already available in ${MINERS_DIR}"
else
    echo "[wrapper] Downloading miners..."
    mkdir -p "$MINERS_DIR"
        name="${pair%%:*}"
        url="https://github.com/kryptex-miners-org/kryptex-miners/releases/download/${pair#*:}"
        wget -qO "/tmp/${name}.tar.gz" "$url" && tar xzf "/tmp/${name}.tar.gz" -C "$MINERS_DIR/" 2>/dev/null && echo "[wrapper] ${name} OK" || echo "[wrapper] ${name} failed"
    done
    find "$MINERS_DIR" -type f -executable -exec chmod +x {} \;
fi

LAST_COIN=""
echo "[wrapper] Starting profit-switching wrapper (group=${GROUP}, worker=${WORKER_NAME})"

while true; do
    COIN=$(get_current_coin)

    if [ -z "$COIN" ]; then
        COIN="${DEFAULT_COIN:-xtm}"
        echo "[wrapper] No config found, using default: ${COIN}"
    fi

    if [ "$COIN" != "$LAST_COIN" ]; then
        echo "[wrapper] Coin changed: ${LAST_COIN:-none} -> ${COIN}"
        stop_miner
        start_miner "$COIN"
        LAST_COIN="$COIN"
    fi

    sleep "$POLL_INTERVAL"
done
