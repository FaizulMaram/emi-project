import math
import os
import socket
from datetime import datetime, timezone

from flask import Flask, jsonify, request
from pymongo import MongoClient

app = Flask(__name__)
client = MongoClient(os.environ["MONGO_URL"], serverSelectionTimeoutMS=3000)
calculations = client.get_default_database(default="emidb")["calculations"]

POD_NAME = os.environ.get("HOSTNAME") or socket.gethostname()
try:
    POD_IP = os.environ.get("POD_IP") or socket.gethostbyname(socket.gethostname())
except OSError:
    POD_IP = "unknown"


def positive_number(value):
    if isinstance(value, bool):
        return None
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    if not math.isfinite(number) or number <= 0:
        return None
    return number


@app.get("/health")
def health():
    try:
        client.admin.command("ping")
        return jsonify(status="ok"), 200
    except Exception:
        return jsonify(status="unavailable"), 503


@app.post("/api/emi")
def calc_emi():
    data = request.get_json(silent=True) or {}
    P = positive_number(data.get("P"))
    rate = positive_number(data.get("rate"))
    n = positive_number(data.get("n"))
    if P is None or rate is None or n is None or n != int(n):
        return jsonify(error="P, rate and n must be positive numbers (n a whole number)"), 400
    n = int(n)

    r = rate / 12 / 100
    try:
        emi = P * r * (1 + r) ** n / ((1 + r) ** n - 1)
    except (OverflowError, ZeroDivisionError):
        return jsonify(error="These values are too large or too small"), 400
    total_payment = emi * n
    total_interest = total_payment - P

    doc = {
        "principal": P, "rate": rate, "months": n,
        "emi": round(emi, 2), "servedBy": POD_NAME,
        "createdAt": datetime.now(timezone.utc),
    }
    try:
        calculations.insert_one(doc)
    except Exception:
        return jsonify(error="Could not save to MongoDB"), 503

    return jsonify(emi=round(emi, 2), totalPayment=round(total_payment, 2),
                   totalInterest=round(total_interest, 2),
                   servedBy=POD_NAME, podIp=POD_IP)


@app.get("/api/history")
def history():
    try:
        rows = list(calculations.find({}, {"_id": 0}).sort("createdAt", -1).limit(10))
    except Exception:
        return jsonify(error="Could not read history"), 503
    for row in rows:
        row["createdAt"] = row["createdAt"].isoformat() + "Z"
    return jsonify(rows)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8080")))