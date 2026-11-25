#!/bin/bash
# Milestone 3 helper. Needs emi.local mapped to the Ingress (see README).
# Usage: selfheal.sh web|mongo
# Runs a request loop through the Ingress and `kubectl get pods -n emi -w`
# while deleting one web pod (web) or the current MongoDB PRIMARY (mongo).
mode=$1
watch=$(mktemp); reqs=$(mktemp)
kubectl get pods -n emi -w --output-watch-events > "$watch" 2>&1 &
w=$!
(
  end=$((SECONDS + 60))
  while [ $SECONDS -lt $end ]; do
    code=$(curl -s -m 5 -o /dev/null -w '%{http_code}' -X POST http://emi.local/api/emi \
      -H 'Content-Type: application/json' -d '{"P":200000,"rate":11,"n":48}')
    echo "$(date -u +%H:%M:%S) $code" >> "$reqs"
    python3 -c 'import time; time.sleep(0.2)'
  done
) &
loop=$!
python3 -c 'import time; time.sleep(5)'

if [ "$mode" = web ]; then
  victim=$(kubectl get pods -n emi -l app=emi-web -o jsonpath='{.items[0].metadata.name}')
else
  victim=$(kubectl exec -n emi mongo-0 -- mongosh --quiet --eval 'db.hello().primary' | cut -d. -f1)
  echo "Current PRIMARY: $victim"
fi
echo "$(date -u +%H:%M:%S) kubectl delete pod $victim -n emi"
kubectl delete pod "$victim" -n emi --wait=false

if [ "$mode" = mongo ]; then
  for i in $(seq 1 30); do
    p=$(kubectl exec -n emi mongo-0 -- mongosh --quiet --eval 'db.hello().primary' 2>/dev/null)
    [ -z "$p" ] && p=$(kubectl exec -n emi mongo-2 -- mongosh --quiet --eval 'db.hello().primary' 2>/dev/null)
    if [ -n "$p" ] && [ "${p%%.*}" != "$victim" ]; then
      echo "$(date -u +%H:%M:%S) new PRIMARY elected: $p"; break
    fi
    python3 -c 'import time; time.sleep(1)'
  done
fi
wait $loop
kill $w 2>/dev/null

echo
echo "--- kubectl get pods -n emi -w"
cat "$watch"
echo
echo "--- request loop through http://emi.local (60 s)"
total=$(wc -l < "$reqs" | tr -d ' ')
ok=$(grep -c ' 200$' "$reqs")
echo "requests: $total   HTTP 200: $ok   other: $((total - ok))"
grep -v ' 200$' "$reqs" | head -20
if [ "$mode" = mongo ]; then
  echo
  echo "--- replica set after the test"
  kubectl exec -n emi mongo-0 -- mongosh --quiet --eval \
    'rs.status().members.forEach(m => print(m.name + "  " + m.stateStr))' 2>/dev/null ||
    kubectl exec -n emi mongo-1 -- mongosh --quiet --eval \
      'rs.status().members.forEach(m => print(m.name + "  " + m.stateStr))'
  echo
  echo "--- latest saved calculations (app still saves)"
  curl -s http://emi.local/api/history | python3 -c '
import sys, json
for r in json.load(sys.stdin)[:3]:
    print(r["createdAt"], r["principal"], r["rate"], r["months"], r["emi"], r["servedBy"])'
fi
rm -f "$watch" "$reqs"
