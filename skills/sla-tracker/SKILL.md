---
name: sla-tracker
description: Cluster uptime monitoring and SLA tracking for NixOS multi-host deployments. Monitor service availability, track uptime percentages, detect SLA breaches, and alert on degraded services. Use this skill whenever the user asks about cluster health, uptime monitoring, SLA compliance, service availability, downtime tracking, or wants to know if their cluster is meeting service level objectives.
---

# SLA Tracker - Cluster Uptime Monitoring

Track service availability and uptime across your NixOS cluster hosts (zephyr, nexus, forge, sentry).

## When to Use This Skill

Use this skill when:
- User asks about cluster health, uptime, or availability
- User mentions SLA, service level agreements, or uptime percentages
- User wants to monitor service downtime or outages
- User asks "is the cluster up?" or "are all nodes running?"
- User wants alerts for service failures
- User needs to generate uptime reports

## Your Cluster Hosts

| Host | Role | Services to Monitor |
|------|------|---------------------|
| zephyr | Workstation + AI | ai-inference-gateway, mining |
| nexus | Gaming + AI + Mining | mining services |
| forge | Mining + AI | mining, ai-inference-gateway |
| sentry | Mining | mining services |

## SLA Basics

### Common SLA Targets

| SLA Level | Uptime | Downtime per month | Downtime per year |
|-----------|--------|-------------------|-------------------|
| 99.9% | "Three nines" | 43.2 minutes | 8.76 hours |
| 99.5% | "Two and a half nines" | 3.6 hours | 43.8 hours |
| 99.0% | "Two nines" | 7.2 hours | 87.6 hours |
| 95.0% | "One and a half nines" | 36 hours | 18.25 days |

### Calculating Uptime

```
Uptime % = (Total Time - Downtime) / Total Time × 100
Downtime = Number of Incidents × Average Recovery Time
```

## Workflow

### Step 1: Check Current Cluster Status

```bash
# Check all hosts connectivity
for host in zephyr nexus forge sentry; do
    echo "=== $host ==="
    ping -c 1 $host.local 2>/dev/null && echo "✓ Online" || echo "✗ Offline"
done

# Or use your justfile recipe
just cluster-status
```

### Step 2: Check Critical Services

```bash
# On each host, check service status
systemctl is-active ai-inference-gateway
systemctl is-active xmrig@*
systemctl is-active lolminer-*

# Get last restart time
systemctl show ai-inference-gateway -p ActiveEnterTimestamp
```

### Step 3: Calculate Service Uptime

For each service, use systemd's runtime tracking:

```bash
# Get service uptime in seconds
UPTIME_SEC=$(systemctl show ai-inference-gateway -p ActiveEnterTimestamp --value | \
    xargs date -d +%s)

NOW_SEC=$(date +%s)
RUNTIME_SEC=$((NOW_SEC - UPTIME_SEC))
RUNTIME_HOURS=$((RUNTIME_SEC / 3600))

echo "Service has been running for $RUNTIME_HOURS hours"
```

### Step 4: Create Uptime Monitoring Script

Create `/etc/nixos/scripts/check-uptime.sh`:

```bash
#!/usr/bin/env bash
# Check cluster uptime and report SLA status

REPORT_FILE="/var/log/cluster-uptime.log"
ALERT_THRESHOLD=95  # Alert if uptime below 95%

{
    echo "=== Cluster Uptime Report - $(date) ==="

    for host in zephyr nexus forge sentry; do
        echo ""
        echo "Host: $host"

        # Check host up
        if ping -c 1 -W 2 "$host.local" >/dev/null 2>&1; then
            echo "  Status: Online"

            # Check services (run via SSH if remote)
            if [ "$host" != "$(hostname)" ]; then
                ssh "$host.local" 'systemctl list-units --failed --no-legend --plain' || true
            else
                systemctl list-units --failed --no-legend --plain || true
            fi
        else
            echo "  Status: OFFLINE - SLA BREACH"
        fi
    done

    echo ""
    echo "=== SLA Summary ==="
    echo "Check individual service logs for detailed uptime"

} | tee -a "$REPORT_FILE"
```

### Step 5: Set Up Uptime Tracking Database

For proper SLA tracking, create a simple uptime log:

```bash
# Create systemd service to log uptime every 5 minutes
cat > /etc/systemd/system/uptime-logger.service <<'EOF'
[Unit]
Description=Log cluster uptime for SLA tracking

[Service]
Type=oneshot
ExecStart=/etc/nixos/scripts/check-uptime.sh
EOF

cat > /etc/systemd/system/uptime-logger.timer <<'EOF'
[Unit]
Description=Log uptime every 5 minutes

[Timer]
OnCalendar=*:0/5
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now uptime-logger.timer
```

### Step 6: Generate SLA Reports

Create a report generator:

```bash
#!/usr/bin/env bash
# Generate SLA compliance report

LOG_FILE="/var/log/cluster-uptime.log"
REPORT_PERIOD_DAYS=30

# Calculate uptime percentage
# This analyzes the log file for "OFFLINE" entries
TOTAL_CHECKS=$(grep -c "Host:" "$LOG_FILE" 2>/dev/null || echo "1")
OFFLINE_COUNT=$(grep -c "OFFLINE" "$LOG_FILE" 2>/dev/null || echo "0")

UPTIME_PCT=$(echo "scale=2; ($TOTAL_CHECKS - $OFFLINE_COUNT) * 100 / $TOTAL_CHECKS" | bc)

cat <<EOF
=== SLA Report (Last $REPORT_PERIOD_DAYS days) ===
Overall Uptime: ${UPTIME_PCT}%
Total Checks: $TOTAL_CHECKS
Offline Incidents: $OFFLINE_COUNT

SLA Status: $(echo "$UPTIME_PCT >= 99" | bc -l >/dev/null && echo "COMPLIANT" || echo "BREACH")

Per-Host Status:
EOF

# Per-host breakdown
for host in zephyr nexus forge sentry; do
    HOST_CHECKS=$(grep "Host: $host" "$LOG_FILE" | wc -l)
    HOST_OFFLINE=$(grep "Host: $host" "$LOG_FILE" | grep -c "OFFLINE" || echo "0")
    HOST_UPTIME=$(echo "scale=2; ($HOST_CHECKS - $HOST_OFFLINE) * 100 / $HOST_CHECKS" | bc)

    echo "  $host: ${HOST_UPTIME}% (${HOST_OFFLINE} incidents)"
done
```

## Quick Commands

```bash
# Check all hosts now
for host in zephyr nexus forge sentry; do ping -c 1 $host.local && echo "$host: ✓" || echo "$host: ✗"; done

# Check failed services locally
systemctl --failed

# Check service uptime
systemctl show ai-inference-gateway -p ActiveEnterTimestamp --value

# View recent downtime
grep "OFFLINE" /var/log/cluster-uptime.log | tail -20

# Get uptime report
/etc/nixos/scripts/sla-report.sh
```

## Alerting on SLA Breach

Create a simple alert script:

```bash
#!/usr/bin/env bash
# Check SLA and alert on breach
UPTIME_PCT=$1
THRESHOLD=$2  # e.g., 99

if (( $(echo "$UPTIME_PCT < $THRESHOLD" | bc -l) )); then
    logger -t sla-alert "SLA BREACH: Uptime ${UPTIME_PCT}% below ${THRESHOLD}%"
    # Could send webhook, email, etc.
fi
```

## Integration with Existing Monitoring

Your cluster already has:
- `lm-sensors` for hardware monitoring
- Prometheus metrics at `http://127.0.0.1:8080/metrics`

Add SLA tracking metrics:

```python
# In ai-inference-gateway or similar
from prometheus_client import Gauge, Counter

# SLA metrics
uptime_gauge = Gauge('cluster_uptime_percent', 'Cluster uptime percentage', ['host'])
incident_counter = Counter('sla_breach_total', 'SLA breach incidents', ['host', 'service'])
```
