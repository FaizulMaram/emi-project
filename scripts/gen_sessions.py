import random
# (rate, duration_s) -> file with rate*duration sessions
combos = [(r, 60) for r in (10, 25, 50, 100, 200)] + [(10, 120), (100, 300), (10, 180)]
for rate, dur in combos:
    with open(f"scripts/sessions_{rate}_{dur}.txt", "w") as f:
        for _ in range(rate * dur):
            body = '{"P":%d,"rate":%.2f,"n":%d}' % (
                random.randint(10000, 1000000),
                random.uniform(1, 25),
                random.randint(6, 360))
            f.write(f"/api/emi method=POST contents='{body}'\n\n")
print("done")