import sys, os, time, csv, json, subprocess, threading, signal, psutil
label = sys.argv[1]
hpa = "--hpa" in sys.argv
stop = threading.Event()
signal.signal(signal.SIGTERM, lambda *a: stop.set())
signal.signal(signal.SIGINT, lambda *a: stop.set())
os.makedirs("results", exist_ok=True)

def host():
    with open(f"results/{label}_host.csv", "w", newline="") as f:
        w = csv.writer(f); w.writerow(["timestamp", "cpu_percent"])
        while not stop.is_set():
            c = psutil.cpu_percent(interval=1)
            w.writerow([round(time.time(), 1), c]); f.flush()

def pods():
    with open(f"results/{label}_pods.csv", "w", newline="") as f:
        w = csv.writer(f); w.writerow(["timestamp", "pod", "cpu_m", "mem_Mi"])
        while not stop.is_set():
            ts = round(time.time(), 1)
            out = subprocess.run(["kubectl", "top", "pods", "-n", "emi", "--no-headers"],
                                 capture_output=True, text=True).stdout
            for line in out.strip().splitlines():
                p = line.split()
                if len(p) >= 3:
                    w.writerow([ts, p[0], p[1].rstrip("m"), p[2].rstrip("Mi")])
            f.flush()
            stop.wait(15)

def hpa_loop():
    with open(f"results/{label}_hpa.csv", "w", newline="") as f:
        w = csv.writer(f); w.writerow(["timestamp", "current_replicas", "desired_replicas", "cpu_util_percent"])
        while not stop.is_set():
            ts = round(time.time(), 1)
            out = subprocess.run(["kubectl", "get", "hpa", "emi-web", "-n", "emi", "-o", "json"],
                                 capture_output=True, text=True).stdout
            try:
                s = json.loads(out)["status"]
                m = s.get("currentMetrics") or [{}]
                util = m[0].get("resource", {}).get("current", {}).get("averageUtilization", "")
                w.writerow([ts, s.get("currentReplicas", ""), s.get("desiredReplicas", ""), util])
                f.flush()
            except Exception:
                pass
            stop.wait(15)

targets = [host, pods] + ([hpa_loop] if hpa else [])
threads = [threading.Thread(target=t, daemon=True) for t in targets]
for t in threads: t.start()
stop.wait()
for t in threads: t.join(timeout=5)