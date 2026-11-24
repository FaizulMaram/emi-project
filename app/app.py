import os
from flask import Flask, jsonify
from pymongo import MongoClient

app = Flask(__name__)
client = MongoClient(os.environ["MONGO_URL"], serverSelectionTimeoutMS=3000)

@app.get("/health")
def health():
    try:
        client.admin.command("ping")
        return jsonify(status="ok"), 200
    except Exception:
        return jsonify(status="unavailable"), 503

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)