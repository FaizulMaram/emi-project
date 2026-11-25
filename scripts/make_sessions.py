import json
import random

random.seed(584)

with open("scripts/sessions.txt", "w") as f:
    for _ in range(1000):
        body = json.dumps(
            {
                "P": random.randint(1000, 1000000),
                "rate": round(random.uniform(1, 30), 2),
                "n": random.randint(1, 360),
            },
            separators=(",", ":"),
        )
        f.write(f"/api/emi method=POST contents='{body}'\n\n")