# Loan EMI Calculator on Kubernetes (Minikube)

DS-584 Cloud Computing, Assignment 4.

A Flask web app that calculates loan EMIs and stores every calculation in a
3-member MongoDB replica set. It runs on a single-node Minikube cluster: the web
Deployment sits behind a ClusterIP Service, traffic comes in through the NGINX
Ingress controller, and a Horizontal Pod Autoscaler scales the web pods from 1 to 5.

```
host ──HTTP──> Ingress (nginx, emi.local) ──> Service emi-web ──> emi-web pods (1–5, HPA)
                                                                    │ MONGO_URL
                                                                    ▼
                                              StatefulSet mongo: mongo-0, mongo-1, mongo-2 (rs0, 1Gi PVC each)
```

## Repository layout

| Path | Contents |
|---|---|
| `app/` | Flask app (`app.py`), page (`static/index.html`), `Dockerfile`, `.dockerignore`, `requirements.txt` |
| `k8s/` | All manifests: namespace, ConfigMap, MongoDB headless Service + StatefulSet, `mongo-init` Job, web Deployment + Service, Ingress, HPA |
| `scripts/` | Load generation, profiling, experiment runners and plotting |
| `results/` | Raw outputs from every test, plus the three graphs |

## The application

| Endpoint | Behaviour |
|---|---|
| `GET /` | Bootstrap + jQuery page. The form submits with AJAX (no postback); only the result panel and history table update. |
| `POST /api/emi` | Body `{"P": 500000, "rate": 12, "n": 24}`. Returns `emi`, `totalPayment`, `totalInterest`, `servedBy` (pod name from `HOSTNAME`) and `podIp`. Saves the calculation to MongoDB. |
| `GET /api/history` | Last 10 calculations, newest first. |
| `GET /health` | `200` only when MongoDB answers a ping, otherwise `503`. Used by the readiness and liveness probes. |

EMI = P·r·(1+r)ⁿ / ((1+r)ⁿ − 1), where r = annual rate ÷ 12 ÷ 100 and n is months.

Inputs are validated on the client and again on the server: all three must be
positive numbers and `n` must be a whole number. Invalid input gets a `400`.

Each calculation is stored in the `calculations` collection of `emidb` with the
fields `principal`, `rate`, `months`, `emi`, `servedBy` and `createdAt`.

The MongoDB connection string is read from the `MONGO_URL` environment variable.
The source code contains no host names, IP addresses or passwords.

## Prerequisites

- Docker
- [Minikube](https://minikube.sigs.k8s.io/docs/start/) and `kubectl`
- For Milestone 4: `httperf`, plus Python 3 with `psutil`, `pandas` and
  `matplotlib`

## Bring up the system on a fresh Minikube cluster

Run these from the repository root.

**1. Start Minikube and enable the add-ons**

```bash
minikube start --driver=docker
minikube addons enable ingress          # NGINX Ingress controller
minikube addons enable metrics-server   # needed by kubectl top and the HPA
```

**2. Build the image and load it into Minikube**

```bash
docker build -t emi-web:1.0 app/
minikube image load emi-web:1.0
```

Alternatively, build straight into Minikube's Docker daemon:
`eval $(minikube docker-env) && docker build -t emi-web:1.0 app/`.
The Deployment uses `imagePullPolicy: IfNotPresent`, so it never tries to pull
`emi-web` from a registry.

**3. Apply every manifest**

```bash
kubectl apply -f k8s/
```

`kubectl` applies the files in alphabetical order, so `00-namespace.yaml`
creates the `emi` namespace before anything else needs it. This one command
creates:

- the `emi-config` ConfigMap holding `MONGO_URL`
  (`mongodb://mongo-0.mongo:27017,mongo-1.mongo:27017,mongo-2.mongo:27017/emidb?replicaSet=rs0`)
- the headless Service `mongo` and the StatefulSet `mongo` (3 replicas,
  `--replSet rs0 --bind_ip_all`, one 1Gi PVC each from the `standard` StorageClass)
- the `mongo-init` Job, which runs `rs.initiate()` against `mongo-0.mongo` with
  all three members. It retries until the mongo pods are up.
- the `emi-web` Deployment (3 replicas, probes on `/health`, requests
  `100m`/`128Mi`, limits `250m`/`256Mi`) and its ClusterIP Service on port 80.
  A `preStop` hook waits 10 s before a pod shuts down, so the Ingress stops
  routing to it first and no requests fail when pods are deleted or replaced.
- the `emi-ingress` Ingress for host `emi.local`
- the `emi-web` HPA (1–5 replicas, 50% average CPU)

The web pods report *not ready* until the replica set has a PRIMARY, which
usually takes a minute or two after the first apply.

> The HPA starts working straight away and will scale the idle Deployment down
> to 1 pod. For the fixed-replica experiments, delete it first:
> `kubectl delete hpa emi-web -n emi`. The experiment scripts do this for you.

**4. Wait for everything to be ready**

```bash
kubectl wait --for=condition=complete job/mongo-init -n emi --timeout=300s
kubectl rollout status statefulset/mongo -n emi
kubectl rollout status deployment/emi-web -n emi
kubectl get all,pvc,configmap -n emi -o wide
```

Check the replica set (expect one PRIMARY and two SECONDARY):

```bash
kubectl logs job/mongo-init -n emi
kubectl exec -n emi mongo-0 -- mongosh --quiet --eval \
  'rs.status().members.forEach(m => print(m.name, m.stateStr))'
```

**5. Open the app**

Through a port-forward:

```bash
kubectl port-forward svc/emi-web 8080:80 -n emi
# open http://localhost:8080
```

Through the Ingress, map `emi.local` in your hosts file (`/etc/hosts`, or
`C:\Windows\System32\drivers\etc\hosts` on Windows):

- **Linux:** add `<output of minikube ip>  emi.local`
- **macOS / Windows with the Docker driver:** run `minikube tunnel` in its own
  terminal and add `127.0.0.1  emi.local`

Then open <http://emi.local>.

Quick check from the command line:

```bash
curl -s -X POST http://emi.local/api/emi \
  -H 'Content-Type: application/json' -d '{"P":500000,"rate":12,"n":24}'
curl -s http://emi.local/api/history
```

## Milestone tests

**Persistence (Milestone 2).** Delete a mongo pod and check that it comes back
with the same name and PVC, and that the documents are still there:

```bash
kubectl exec -n emi mongo-0 -- mongosh emidb --quiet --eval 'db.calculations.countDocuments()'
kubectl delete pod mongo-1 -n emi
kubectl get pods,pvc -n emi    # mongo-1 is recreated and bound to data-mongo-1 again
kubectl exec -n emi mongo-0 -- mongosh emidb --quiet --eval 'db.calculations.countDocuments()'
```

**Helper scripts (Milestone 3).** These produced the files in `results/m3_*`.
Run them from the repository root while `emi.local` reaches the Ingress:

| Script | What it does |
|---|---|
| `scripts/dist.sh` | Sends 30 `POST /api/emi` requests and counts `servedBy` per pod. |
| `scripts/scale5.sh` | Scales 3 → 5 replicas under a request loop and compares each new pod's Ready time with its first served request. |
| `scripts/selfheal.sh web\|mongo` | Deletes a web pod, or the current MongoDB PRIMARY, while a request loop and `kubectl get pods -w` run. |
| `scripts/rollout.sh update\|undo` | Runs `kubectl set image ... emi-web:1.1` or `kubectl rollout undo` under a request loop and reports failed requests. |

**Load distribution (Milestone 3).** Send 30 requests through the Ingress and
count them by `servedBy`:

```bash
for i in $(seq 30); do
  curl -s -X POST http://emi.local/api/emi -H 'Content-Type: application/json' \
    -d '{"P":500000,"rate":12,"n":24}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["servedBy"])'
done | sort | uniq -c
kubectl scale deployment emi-web --replicas=5 -n emi   # then repeat the loop
```

**Self-healing (Milestone 3).** Keep `kubectl get pods -n emi -w` running in
another terminal, then:

```bash
kubectl delete pod <one emi-web pod> -n emi
# find the current PRIMARY and delete it; a new PRIMARY is elected
kubectl exec -n emi mongo-0 -- mongosh --quiet --eval 'db.hello().primary'
kubectl delete pod <primary pod> -n emi
```

**Rolling update and rollback (Milestone 3).** Version 1.1 differs from 1.0
only in the page footer. Change `version 1.0` to `version 1.1` in
`app/static/index.html`, then:

```bash
docker build -t emi-web:1.1 app/ && minikube image load emi-web:1.1
kubectl set image deployment/emi-web emi-web=emi-web:1.1 -n emi
kubectl rollout status deployment/emi-web -n emi
kubectl rollout history deployment/emi-web -n emi
kubectl rollout undo deployment/emi-web -n emi       # back to emi-web:1.0
```

Keep a request loop running against `http://emi.local/api/emi` during the
update. `results/rolling-update-requests.log` shows every request returning `200`.

## Load testing and autoscaling (Milestone 4)

Every request is a `POST /api/emi` to `http://emi.local/` with random valid
inputs, so every request also writes to MongoDB.

| Script | Purpose |
|---|---|
| `scripts/make_sessions.py` | Builds `scripts/sessions.txt`: 1000 httperf sessions, each one POST with random valid P, rate and n. httperf accepts at most 1000 sessions per file and cycles through them for longer runs. |
| `scripts/run_experiments.sh` | The 15 fixed-replica runs (1, 2 and 3 replicas × 10, 25, 50, 100, 200 req/s, 60 s each) using `httperf`. |
| `scripts/profile.py` | Records `kubectl top pods -n emi` every 15 s and host CPU every 1 s (psutil) to timestamped CSVs. With `--hpa` it also records `kubectl get hpa emi-web` every 15 s. |
| `scripts/autoscale_test.sh [peak] [label]` | Applies the HPA and runs the 10-minute test with `httperf`: 2 min at 10 req/s, 5 min at `peak` req/s (default 100), 3 min at 10 req/s. Output files start with `label` (default `autoscale`). |
| `scripts/plot.py` | Reads `results/` and writes `summary.csv` and graphs 1–3. |

Run them from the repository root:

```bash
python3 scripts/make_sessions.py
bash scripts/run_experiments.sh
bash scripts/autoscale_test.sh
python3 scripts/plot.py
```

All load in `results/` was generated with `httperf` through the Ingress at
`http://emi.local/`.

## Results

All raw output is in `results/`:

| File | Contents |
|---|---|
| `run_r<replicas>_rate<rate>.txt` | Full httperf output of each fixed-replica run: requests, replies, average response time, status codes, errors |
| `r<replicas>_rate<rate>_pods.csv` | Per-pod CPU (millicores) and memory (MiB) every 15 s |
| `r<replicas>_rate<rate>_host.csv` | Host CPU % every second |
| `summary.csv` | All 15 runs in one table |
| `autoscale_*.csv`, `autoscale_*.txt` | Autoscaling test: phases, HPA replicas and CPU, pod and host CPU |
| `m2_*.txt` | Milestone 2 output: `kubectl get all,pvc,configmap`, `rs.status()`, mongo-init logs, persistence test |
| `m3_*.txt`, `m3_*_requests.log` | Milestone 3 output: Ingress, requests per pod (3 and 5 replicas), readiness, self-healing, rolling update and rollback, with the request-loop logs |
| `graph1_response_time.png` | Average response time vs request rate for 1, 2 and 3 replicas |
| `graph2_pod_cpu.png` | Per-pod CPU over time, 100 req/s with 3 replicas |
| `graph3_autoscaling.png` | Request rate, average CPU and replica count over the 10-minute autoscaling test |

Fixed-replica runs (from `results/summary.csv`, httperf, 60 s each): average
response time in ms, with failed requests / total requests in brackets. A
request counts as failed when it got no 2xx reply (timeout, refused
connection, or a 4xx/5xx status).

| Rate (req/s) | 1 replica | 2 replicas | 3 replicas |
|---|---|---|---|
| 10 | 5.2 (0 / 600) | 4.6 (0 / 600) | 5.2 (0 / 600) |
| 25 | 4.7 (0 / 1500) | 4.3 (0 / 1500) | 4.3 (0 / 1500) |
| 50 | 4.0 (0 / 3000) | 4.9 (0 / 3000) | 4.2 (0 / 3000) |
| 100 | 3.4 (0 / 6000) | 4.1 (0 / 6000) | 3.7 (0 / 6000) |
| 200 | 4.1 (0 / 12000) | 3.7 (0 / 12000) | 3.6 (0 / 12000) |

Every run completed with zero failed requests. Response time stays at about
4 ms at every rate, because a single pod handles 200 req/s using about 63m of
CPU (well under its 250m limit), so extra replicas do not change latency at
these rates.

**Autoscaling test** (`results/autoscale_*`, Graph 3). With the HPA at 1–5
replicas and a 50% CPU target, the load ran 2 min at 10 req/s, 5 min at
100 req/s, then 3 min at 10 req/s. Under 100 req/s the average CPU rose to 100%
of the request, and the HPA scaled `emi-web` from 1 to 2, then 3 replicas,
which brought CPU back to about 43%. When the load dropped to 10 req/s it
scaled back down.

## Tear down

```bash
kubectl delete -f k8s/    # deleting the emi namespace also removes the mongo PVCs
minikube delete           # or remove the whole cluster
```
