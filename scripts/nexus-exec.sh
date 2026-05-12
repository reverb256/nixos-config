#!/usr/bin/env bash
# nexus-exec — execute commands on Nexus from Hermes on Zephyr
# Tries SSH-tunneled Unix socket first, falls back to SSH ControlMaster.
set -euo pipefail
SOCKET="${NEXUS_EXEC_SOCKET:-/tmp/nexus-exec.sock}"
CWD="${PWD}"
ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in --cwd) CWD="$2"; shift 2 ;; *) ARGS+=("$1"); shift ;; esac
done
if [[ ${#ARGS[@]} -eq 0 ]]; then
    echo "Usage: nexus-exec [--cwd <dir>] <command>" >&2; exit 1
fi
CMD="${ARGS[*]}"

# Try socket path first (fast path — ~1-5ms)
if [[ -S "$SOCKET" ]]; then
    exec 3<>/dev/tcp/localhost/0 2>/dev/null || true  # dummy to avoid unbound var
    python3 -c "
import json, os, socket, sys
try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(10)
    s.connect('$SOCKET')
    import shlex
    req = json.dumps({'id': '1', 'cmd': '''$CMD''', 'cwd': '''$CWD''', 'env': {}})
    s.sendall(req.encode('utf-8') + b'\\n')
    s.shutdown(socket.SHUT_WR)
    resp = b''
    while True:
        chunk = s.recv(4096)
        if not chunk: break
        resp += chunk
    s.close()
    result = json.loads(resp.decode('utf-8'))
    if 'error' in result:
        print(result['error'], file=sys.stderr); sys.exit(1)
    if result.get('stdout'): print(result['stdout'], end='')
    if result.get('stderr'): print(result['stderr'], file=sys.stderr, end='')
    sys.exit(result.get('exit', 1))
except Exception:
    sys.exit(42)
" && exit 0 || [ $? -eq 42 ] || exit $?
fi

# Fallback: SSH via ControlMaster (fast path — ~30-50ms)
exec ssh nexus "cd '${CWD}' && exec ${CMD}"
