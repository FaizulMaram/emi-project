import re
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

# Graph 1
rows = []
for R in (1, 2, 3):
    for rate in (10, 25, 50, 100, 200):
        try:
            t = open(f"results/run_r{R}_rate{rate}.txt").read()
            rows.append(dict(
                replicas=R, rate=rate,
                avg_response_ms=float(re.search(r"Reply time \[ms\]: response ([\d.]+)", t).group(1)),
                actual_reply_rate=float(re.search(r"Reply rate \[replies/s\]: min [\d.]+ avg ([\d.]+)", t).group(1)),
                requests=int(re.search(r"requests (\d+)", t).group(1)),
                replies=int(re.search(r"replies (\d+)", t).group(1)),
                errors=int(re.search(r"Errors: total (\d+)", t).group(1)),
                status_2xx=int(re.search(r"2xx=(\d+)", t).group(1))))
        except Exception as e:
            print("skip", R, rate, e)
df = pd.DataFrame(rows)
# failed = client-side errors (timeouts, refused, reset) + replies that were not 2xx
df["failed"] = df["errors"] + df["replies"] - df["status_2xx"]
df.to_csv("results/summary.csv", index=False)
print(df.to_string(index=False))

plt.figure(figsize=(7, 4.5))
for R, g in df.groupby("replicas"):
    plt.plot(g["rate"], g["avg_response_ms"], marker="o", label=f"{R} replica(s)")
plt.xlabel("Request rate (req/s)"); plt.ylabel("Average response time (ms)")
plt.ylim(bottom=0)
plt.title("Graph 1: Response time vs request rate"); plt.grid(alpha=.3); plt.legend()
plt.tight_layout(); plt.savefig("results/graph1_response_time.png", dpi=150); plt.close()

# Graph 2: per-pod CPU, 100 req/s, 3 replicas (100m request => 1m = 1%)
p = pd.read_csv("results/r3_rate100_pods.csv")
p = p[p["pod"].str.startswith("emi-web")]
p["t"] = p["timestamp"] - p["timestamp"].min()
plt.figure(figsize=(7, 4.5))
for pod, g in p.groupby("pod"):
    plt.plot(g["t"], g["cpu_m"], marker="o", label=pod[-5:])
plt.xlabel("Time (s)"); plt.ylabel("CPU utilization (% of 100m request)")
plt.ylim(0, 100)
plt.title("Graph 2: Per-pod CPU, 100 req/s, 3 replicas"); plt.grid(alpha=.3); plt.legend()
plt.tight_layout(); plt.savefig("results/graph2_pod_cpu.png", dpi=150); plt.close()

# Graph 3: autoscaling


def graph3(label, out, title):
    h = pd.read_csv(f"results/{label}_hpa.csv")
    ph = pd.read_csv(f"results/{label}_phases.csv")
    t0 = ph["timestamp"].iloc[0]
    h["t"] = (h["timestamp"] - t0) / 60
    ph["t"] = (ph["timestamp"] - t0) / 60
    fig, ax = plt.subplots(3, 1, figsize=(8, 8), sharex=True)
    ax[0].step(ph["t"], ph["rate"], where="post"); ax[0].set_ylabel("Request rate (req/s)")
    ax[1].plot(h["t"], h["cpu_util_percent"], marker="o"); ax[1].axhline(50, ls="--", c="gray")
    ax[1].set_ylabel("Avg CPU utilization (%)")
    ax[2].step(h["t"], h["current_replicas"], where="post"); ax[2].set_ylabel("Web replicas")
    ax[2].set_ylim(0, 5.5)
    ax[2].set_xlabel("Time (minutes)")
    for a in ax: a.grid(alpha=.3)
    ax[0].set_title(title)
    plt.tight_layout(); plt.savefig(out, dpi=150); plt.close()


graph3("autoscale", "results/graph3_autoscaling.png",
       "Graph 3: Autoscaling test (10 / 100 / 10 req/s)")
print("graphs saved in results/")
