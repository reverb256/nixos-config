#!/usr/bin/env bash
# Quick Status Check for GPU Schedulers
# CLI-based monitoring (no web UI required)

echo "=== GPU Scheduler Status ==="
echo ""

echo "📊 Scheduler Health:"
echo "  YuniKorn: $(kubectl get pods -n yunikorn -l app=yunikorn-scheduler --no-headers 2>/dev/null | wc -l) pods"
echo "  Volcano: $(kubectl get pods -n volcano-system -l app=volcano-scheduler --no-headers 2>/dev/null | wc -l) pods"
echo ""

echo "🎮 Workloads:"
echo "  Mining pods: $(kubectl get pods -n mining -l app=gpu-miner --no-headers 2>/dev/null | wc -l)"
echo "  AI Gateway pods: $(kubectl get pods -n ai-inference -l app=ai-inference-gateway --no-headers 2>/dev/null | wc -l)"
echo ""

echo "💾 State Management:"
STATE=$(kubectl get configmap gpu-scheduler-state -n kube-system -o jsonpath='{.data.ai-state}' 2>/dev/null)
WORKLOAD=$(kubectl get configmap gpu-scheduler-state -n kube-system -o jsonpath='{.data.active-workload}' 2>/dev/null)
UPDATED=$(kubectl get configmap gpu-scheduler-state -n kube-system -o jsonpath='{.data.last-updated}' 2>/dev/null)
echo "  Current state: ${STATE:-Unknown}"
echo "  Active workload: ${WORKLOAD:-None}"
echo "  Last updated: ${UPDATED:-Never}"
echo ""

echo "📋 Recent Scheduler Events:"
kubectl get events -A --field-selector involvedObject.kind=Pod -l 'app in (gpu-miner,ai-inference-gateway)' --sort-by='.lastTimestamp' 2>/dev/null | tail -5 || echo "  No recent events"
echo ""

echo "⚡ Quick Actions:"
echo "  # Watch pods in real-time"
echo "  watch kubectl get pods -A -l 'app in (gpu-miner,ai-inference-gateway)'"
echo ""
echo "  # Check YuniKorn logs"
echo "  kubectl logs -n yunikorn deployment/yunikorn-scheduler --tail=20"
echo ""
echo "  # Check Volcano logs"
echo "  kubectl logs -n volcano-system deployment/volcano-scheduler --tail=20"
echo ""
