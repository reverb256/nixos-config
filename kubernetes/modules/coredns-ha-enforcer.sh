CURRENT=$(kubectl get deploy coredns -o jsonpath='{.spec.replicas}')
if [ "$CURRENT" -lt 2 ]; then
  kubectl scale deploy coredns --replicas=2
  echo "$(date): Scaled coredns from $CURRENT to 2 replicas"
else
  echo "$(date): CoreDNS already at $CURRENT replicas"
fi
