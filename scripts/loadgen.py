import sys, time, random, json, threading, statistics, requests
from concurrent.futures import ThreadPoolExecutor

rate = float(sys.argv[1]); dur = float(sys.argv[2]); out = sys.argv[3]
url = "http://emi.local/api/emi"
lat, errs, codes = [], [0], {}
lock = threading.Lock()
sess = threading.local()

def one():
    if not hasattr(sess, "s"):
        sess.s = requests.Session()
    body = {"P": random.randint(10000, 1000000),
            "rate": round(random.uniform(1, 25), 2),
            "n": random.randint(6, 360)}
    t = time.time()
    try:
        r = sess.s.post(url, json=body, timeout=5)
        d = (time.time() - t) * 1000
        with lock:
            lat.append(d); codes[r.status_code] = codes.get(r.status_code, 0) + 1
    except Exception:
        with lock: errs[0] += 1

start = time.time(); n = int(rate * dur)
with ThreadPoolExecutor(max_workers=min(400, int(rate * 5) + 20)) as ex:
    for i in range(n):
        target = start + i / rate
        d = target - time.time()
        if d > 0: time.sleep(d)
        ex.submit(one)
elapsed = time.time() - start

with open(out, "w") as f:
    f.write(f"Total: requests {n} replies {len(lat)} test-duration {elapsed:.3f} s\n")
    f.write(f"Reply rate [replies/s]: min 0 avg {len(lat)/elapsed:.1f} max 0\n")
    f.write(f"Reply time [ms]: response {statistics.mean(lat) if lat else 0:.1f}\n")
    f.write(f"Reply status: " + " ".join(f"{k}={v}" for k, v in sorted(codes.items())) + f" 2xx={sum(v for k,v in codes.items() if 200<=k<300)}\n")
    f.write(f"Errors: total {errs[0]}\n")
print(open(out).read())
