#!/usr/bin/env bash
# Watch GPU Scheduler Status in Real-Time
# CLI-based live monitoring (no web UI required)

watch -n 5 '
echo "=== GPU Scheduler Live Status ==="
echo ""
echo "📊 Schedulers:"
echo "  YuniKorn: $(kubectl get pods -n yunikorn -l app=yunikorn-scheduler --no-headers 2>/dev/null | wc -l) pods"
echo "  Volcano: $(kubectl get pods -n volcano-system -l app=volcano-scheduler --no-headers 2>/dev/null | wc -l) pods"
echo ""
echo "🎮 GPU Workloads:"
kubectl get pods -A -l "app in (gpu-miner,ai-inference-gateway)" -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase,SCHEDULER:.spec.schedulerName,PRIORITY:.spec.priorityClassName 2>/dev/null | head -10
echo ""
echo "💾 State:"
kubectl get configmap gpu-scheduler-state -n kube-system -o jsonpath="State: {.data.ai-state}{@=" | Workload: {.data.active-workload}{@=" | Updated: {.data.last-updated}" 2>/dev/null
echo ""
echo "⏰ Last update: $(date)"
'
