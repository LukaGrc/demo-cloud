import logging
import os

import psycopg2
import psycopg2.extras
from dotenv import load_dotenv
from flask import Flask, jsonify, request
from flask_cors import CORS

load_dotenv()

app = Flask(__name__)
CORS(app)

DATABASE_URL = os.environ.get("DATABASE_URL")


def open_db():
    return psycopg2.connect(DATABASE_URL, connect_timeout=5)


def setup_schema():
    try:
        conn = open_db()
        with conn:
            with conn.cursor() as cur:
                cur.execute("""
                    CREATE TABLE IF NOT EXISTS file_records (
                        id SERIAL PRIMARY KEY,
                        name VARCHAR(255) NOT NULL,
                        size INTEGER NOT NULL,
                        stored_at TIMESTAMPTZ DEFAULT NOW()
                    )
                """)
        conn.close()
        logging.info("Schema ready")
    except Exception as e:
        logging.error(f"Schema setup failed: {e}")


setup_schema()


@app.route("/health")
def health():
    return jsonify({"status": "ok", "message": "healthy"})


@app.route("/healthz/ready")
def readiness():
    try:
        conn = open_db()
        with conn.cursor() as cur:
            cur.execute("SELECT 1")
        conn.close()
        return jsonify({"status": "ok", "db": "reachable"})
    except Exception as e:
        logging.error(f"Readiness check failed: {e}")
        return jsonify({"status": "error", "db": "unreachable"}), 503


@app.route("/records", methods=["POST"])
def create_record():
    body = request.get_json()
    if not body or "name" not in body or "size" not in body:
        return jsonify({"error": "Missing name or size field"}), 400

    try:
        conn = open_db()
        with conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO file_records (name, size) VALUES (%s, %s)",
                    (body["name"], body["size"]),
                )
        conn.close()
    except Exception as e:
        logging.error(f"DB insert failed: {e}")
        return jsonify({"error": str(e)}), 500

    return jsonify({"status": "ok", "message": f"Record for '{body['name']}' created"}), 201


@app.route("/records", methods=["GET"])
def list_records():
    try:
        conn = open_db()
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(
                "SELECT id, name, size, stored_at FROM file_records ORDER BY stored_at DESC"
            )
            rows = cur.fetchall()
        conn.close()
    except Exception as e:
        logging.error(e)
        return jsonify({"error": str(e)}), 500

    records = [
        {
            "id": row["id"],
            "name": row["name"],
            "size": row["size"],
            "stored_at": row["stored_at"].isoformat(),
        }
        for row in rows
    ]
    return jsonify({"records": records})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
