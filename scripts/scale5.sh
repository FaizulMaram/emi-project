#!/bin/bash
# Milestone 3 helper. Needs emi.local mapped to the Ingress (see README).
# Scales emi-web from 3 to 5 while a request loop runs, then compares the time
# each new pod became Ready with the time it served its first request.
before=$(kubectl get pods -n emi -l app=emi-web -o jsonpath='{.items[*].metadata.name}')
log=$(mktemp)
(
  end=$((SECONDS + 45))
  while [ $SECONDS -lt $end ]; do
    pod=$(curl -s -m 5 -X POST http://emi.local/api/emi -H 'Content-Type: application/json' \
      -d '{"P":300000,"rate":10,"n":36}' |
      python3 -c 'import sys,json; print(json.load(sys.stdin).get("servedBy","ERROR"))' 2>/dev/null || echo ERROR)
    echo "$(date -u +%H:%M:%S) $pod" >> "$log"
  done
) &
loop=$!
python3 -c 'import time; time.sleep(3)'
echo "$(date -u +%H:%M:%S) kubectl scale deployment emi-web --replicas=5 -n emi"
kubectl scale deployment emi-web --replicas=5 -n emi
wait $loop

echo
echo "New pods: created / Ready (UTC) vs first request served (UTC)"
for p in $(kubectl get pods -n emi -l app=emi-web -o jsonpath='{.items[*].metadata.name}'); do
  case " $before " in *" $p "*) continue ;; esac
  created=$(kubectl get pod "$p" -n emi -o jsonpath='{.metadata.creationTimestamp}' | cut -c12-19)
  ready=$(kubectl get pod "$p" -n emi \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].lastTransitionTime}' | cut -c12-19)
  first=$(grep " $p$" "$log" | head -1 | cut -d' ' -f1)
  echo "  $p  created $created  Ready $ready  first request ${first:-none}"
done
echo
echo "Requests during the 45 s loop: $(wc -l < "$log" | tr -d ' '), failed: $(grep -c ERROR "$log")"
rm -f "$log"
