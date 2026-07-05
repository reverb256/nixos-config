#!/bin/bash
# krash3 autonomous iSCSI debug
# Invoke: sudo bash /tmp/krash3-debug.sh
set +u
mkdir -p /tmp/krash3-iscsi-debug/pcap
RUN=/tmp/krash3-iscsi-debug/runlog.txt
exec > "$RUN" 2>&1
log() { printf "\n########## %s ##########\n" "$1"; }
date
hostname
uname -a

log "A. VM"
virsh list --all
echo "---"
virsh domstate windows
echo "---"
echo "guest-agent ping:"
virsh qemu-agent-command windows '{"execute":"guest-ping"}' 2>&1 | head -3
echo

log "B. LIO full config"
echo "[B.1] targetcli ls / -o tree"
targetcli ls / -o tree 2>&1
echo "[B.2] /tpg1 ls -l"
targetcli /iscsi/iqn.2025-06.lan.krash3:games/tpg1 ls -l 2>&1
echo "[B.3] /tpg1/attribute ls"
targetcli /iscsi/iqn.2025-06.lan.krash3:games/tpg1/attribute ls 2>&1
echo "[B.4] /tpg1/auth ls"
targetcli /iscsi/iqn.2025-06.lan.krash3:games/tpg1/auth ls 2>&1
echo "[B.5] /tpg1/portals ls"
targetcli /iscsi/iqn.2025-06.lan.krash3:games/tpg1/portals ls 2>&1
echo "[B.6] /tpg1/luns ls -l"
targetcli /iscsi/iqn.2025-06.lan.krash3:games/tpg1/luns ls -l 2>&1
echo "[B.7] /tpg1/acls ls -l"
targetcli /iscsi/iqn.2025-06.lan.krash3:games/tpg1/acls/iqn.1991-05.com.microsoft:krash3-vm ls -l 2>&1
echo "[B.8] sysfs tpg1 attrib files"
ls /sys/kernel/config/target/iscsi/iqn.2025-06.lan.krash3:games/tpg1/ 2>&1
echo "--- attrib values:"
for f in auth_type demo_mode_write_protect default_cmdsn_depth prod_mode_shift fabric_gen_sessions_match_all netif_timeout max_data_out_per_conn; do
  printf "  %s = " "$f"
  cat /sys/kernel/config/target/iscsi/iqn.2025-06.lan.krash3:games/tpg1/attrib/$f 2>&1
  echo
done
echo
echo "--- tpg_state / enable:"
cat /sys/kernel/config/target/iscsi/iqn.2025-06.lan.krash3:games/tpg1/enable 2>&1
echo

log "C. ss and listeners on 3260"
echo "[C.1] ss -lntp4"
ss -lntp4 'sport = :3260' 2>&1
echo "[C.2] ss -lntp6"
ss -lntp6 'sport = :3260' 2>&1 || echo "(no v6 :3260)"
echo "[C.3] ss -tnp all :3260"
ss -tnp 'sport = :3260 or dport = :3260' 2>&1
echo

log "D. Linux-side iscsiadm LOGIN TEST"
echo "[D.1] Add node record"
iscsiadm -m node -o new -T iqn.2025-06.lan.krash3:games -p 10.1.1.150:3260 2>&1 || true
iscsiadm -m node -T iqn.2025-06.lan.krash3:games -p 10.1.1.150:3260 -o update -n node.session.auth.authmethod -v None 2>&1
iscsiadm -m node -T iqn.2025-06.lan.krash3:games -p 10.1.1.150:3260 -o update -n node.session.nr_sessions -v 1 2>&1
iscsiadm -m node -T iqn.2025-06.lan.krash3:games -p 10.1.1.150:3260 -o update -n node.startup -v manual 2>&1
echo "[D.2] show node config"
iscsiadm -m node -p 10.1.1.150:3260 -o show 2>&1 | head -40
echo "[D.3] login attempt"
date +"login attempt at %T.iso"
iscsiadm -m node -T iqn.2025-06.lan.krash3:games -p 10.1.1.150:3260 -l 2>&1
sleep 5
echo "[D.4] session -P 2"
iscsiadm -m session -P 2 2>&1
echo "[D.5] session -s"
iscsiadm -m session -s 2>&1
echo "[D.6] lsblk"
lsblk 2>&1
echo "[D.7] /dev/disk/by-path"
ls /dev/disk/by-path/ 2>&1
echo

log "E. dmesg iSCSI recent"
dmesg 2>&1 | grep -Ei 'iscsi|lio|target_core|tcp_invalid' | tail -50
echo "--- journalctl last 5 min iSCSI subset ---"
journalctl -k --since "5 minute ago" 2>&1 | grep -Ei 'iscsi|tcp_invalid' | tail -50
echo

log "F. tcpdump + Windows re-login trigger"
echo "[F.0] starting tcpdump on enp7s0 (60s budget)"
timeout 80 tcpdump -i enp7s0 -U -w /tmp/krash3-iscsi-debug/pcap/windows_login.pcap 'tcp port 3260' 2>/tmp/krash3-iscsi-debug/pcap/tcpdump.err &
TPID=$!
sleep 3

cat > /tmp/krash3-iscsi-debug/gr_ps_f.py <<'PYEOF'
import subprocess, json, base64, time
def ga(j):
    r = subprocess.run(['sudo','virsh','-q','qemu-agent-command','windows', json.dumps(j)],
                       capture_output=True)
    return (json.loads(r.stdout).get('return') if r.returncode == 0 else None)
def run_ps(expr, timeout=80):
    s = '[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; ' + expr + ' | Out-String -Width 4096'
    enc = base64.b64encode(s.encode('utf-16-le')).decode('ascii')
    r = ga({'execute':'guest-exec','arguments':{'path':'powershell.exe','arg':['-NoProfile','-EncodedCommand',enc],'capture-output':True}})
    if not r or 'pid' not in r: return json.dumps(r)
    pid = r['pid']; end = time.time() + timeout; blob = b''
    while time.time() < end:
        st = ga({'execute':'guest-exec-status','arguments':{'pid': pid}})
        if not st: break
        if st.get('exited'):
            od = st.get('out-data',''); ed = st.get('err-data','')
            if od: blob += base64.b64decode(od + '=' * (-len(od) % 4))
            if ed: blob += base64.b64decode(ed + '=' * (-len(ed) % 4))
            break
        time.sleep(0.5)
    return blob.decode('utf-8','replace')
queries = [
    'Update-IscsiTarget -NodeAddress "iqn.2025-06.lan.krash3:games"',
    'Get-IscsiTargetPortal | Update-IscsiTargetPortal',
    'Get-Service msiscsi | Format-List',
]
for q in queries:
    print('--- ' + q + ' ---')
    print(run_ps(q))
    print()
PYEOF
echo "[F.1] running Windows re-login via guest-agent"
python3 /tmp/krash3-iscsi-debug/gr_ps_f.py 2>&1
echo
echo "[F.2] waiting 30s for any login traffic..."
sleep 30
echo "[F.3] stopping tcpdump"
kill $TPID 2>/dev/null
sleep 2
ls -la /tmp/krash3-iscsi-debug/pcap/

log "G. Decode pcap"
PCAP=/tmp/krash3-iscsi-debug/pcap/windows_login.pcap
ls -la $PCAP
echo "tcpdump stderr:"
cat /tmp/krash3-iscsi-debug/pcap/tcpdump.err 2>&1
echo
echo "[G.1] tcpdump text dump (first 250 lines, verbose):"
tcpdump -r $PCAP -nn 'tcp port 3260' 2>&1 | head -250
echo
if hash tshark 2>/dev/null; then
    echo "[G.2] tshark TCP only (first 30):"
    tshark -r $PCAP -Y 'tcp.port==3260' 2>&1 | head -30
    echo "[G.3] tshark iscsi frames (first 60):"
    tshark -r $PCAP -Y 'tcp.port==3260 && iscsi' 2>&1 | head -60
else
    echo "no tshark; attempting tcpdump -X on SYN/RST/FIN:"
    tcpdump -r $PCAP -nn 'tcp port 3260 and (((tcp[tcpflags] & (tcp-syn)) != 0) or (((tcp[tcpflags] & (tcp-fin|tcp-rst)) != 0)))' -X 2>&1 | head -120
fi
echo

log "H. Windows iSCSI service state + last 30 iScsiPrt events"
cat > /tmp/krash3-iscsi-debug/gr_ps_h.py <<'PYEOF'
import subprocess, json, base64, time
def ga(j):
    r = subprocess.run(['sudo','virsh','-q','qemu-agent-command','windows', json.dumps(j)],
                       capture_output=True)
    return (json.loads(r.stdout).get('return') if r.returncode == 0 else None)
def run_ps(expr, timeout=60):
    s = '[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; ' + expr + ' | Out-String -Width 4096'
    enc = base64.b64encode(s.encode('utf-16-le')).decode('ascii')
    r = ga({'execute':'guest-exec','arguments':{'path':'powershell.exe','arg':['-NoProfile','-EncodedCommand',enc],'capture-output':True}})
    if not r or 'pid' not in r: return json.dumps(r)
    pid = r['pid']; end = time.time() + timeout; blob = b''
    while time.time() < end:
        st = ga({'execute':'guest-exec-status','arguments':{'pid': pid}})
        if not st: break
        if st.get('exited'):
            od = st.get('out-data',''); ed = st.get('err-data','')
            if od: blob += base64.b64decode(od + '=' * (-len(od) % 4))
            if ed: blob += base64.b64decode(ed + '=' * (-len(ed) % 4))
            break
        time.sleep(0.5)
    return blob.decode('utf-8','replace')
queries = [
    'Get-Service msiscsi -ErrorAction SilentlyContinue | Format-List Status,StartType,Name',
    'Get-EventLog System -Source "iScsiPrt" -Newest 30 | Format-List TimeGenerated,EntryType,Message',
    'try { Get-MSDSMGlobalSettings -ErrorAction Stop | Format-List } catch { $_.Exception.Message }',
    'reg query "HKLM\\SOFTWARE\\Microsoft\\iSCSI\\Discovery" 2>&1',
    'reg query "HKLM\\SOFTWARE\\Microsoft\\iSCSI Target Portal" 2>&1',
    'Get-NetAdapter | Where-Object {$_.Status -eq "Up"} | Sort-Object ifIndex | Format-Table Name,ifIndex,MacAddress,Status,LinkSpeed',
]
for q in queries:
    print('--- ' + q + ' ---')
    print(run_ps(q))
    print()
PYEOF
python3 /tmp/krash3-iscsi-debug/gr_ps_h.py 2>&1
echo

log "END"
date
echo "RUNLOG=$RUN"
