import io
import logging
import os

import boto3
import requests
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError
from dotenv import load_dotenv
from flask import Flask, jsonify, request, send_file
from flask_cors import CORS

load_dotenv()

app = Flask(__name__)
CORS(app)

BUCKET = os.environ.get("S3_BUCKET_NAME", "")
S3_REGION = os.environ.get("AWS_DEFAULT_REGION", "eu-west-1")
HISTORY_SERVICE_URL = os.environ.get("HISTORY_SERVICE_URL", "http://localhost:8081").rstrip("/")


def storage_client():
    return boto3.client(
        "s3",
        region_name=S3_REGION,
        config=Config(signature_version="s3v4"),
    )


@app.route("/health")
def health():
    return jsonify({"status": "ok", "message": "healthy"})


@app.route("/healthz/ready")
def readiness():
    try:
        s3 = storage_client()
        s3.head_bucket(Bucket=BUCKET)
        return jsonify({"status": "ok", "s3": "reachable"})
    except (ClientError, BotoCoreError) as e:
        logging.error(f"Readiness check failed: {e}")
        return jsonify({"status": "error", "s3": "unreachable"}), 503


@app.route("/objects", methods=["GET"])
def list_objects():
    try:
        s3 = storage_client()
        response = s3.list_objects_v2(Bucket=BUCKET)
        items = [
            {"name": obj["Key"], "size": obj["Size"],
             "last_modified": obj["LastModified"].isoformat()}
            for obj in response.get("Contents", [])
        ]
    except (ClientError, BotoCoreError) as e:
        logging.error(e)
        return jsonify({"error": str(e)}), 500
    return jsonify({"objects": items})


@app.route("/object/<path:filename>", methods=["GET"])
def get_object(filename):
    try:
        s3 = storage_client()
        obj = s3.get_object(Bucket=BUCKET, Key=filename)
        content = obj["Body"].read().decode("utf-8")
    except (ClientError, BotoCoreError) as e:
        logging.error(e)
        return jsonify({"error": str(e)}), 500
    return jsonify({"content": content})


@app.route("/object/<path:filename>", methods=["PUT"])
def update_object(filename):
    body = request.get_json()
    if not body or "content" not in body:
        return jsonify({"error": "Missing content field"}), 400
    if not filename.endswith(".md"):
        return jsonify({"error": "Only .md files are accepted"}), 400
    try:
        s3 = storage_client()
        s3.put_object(Bucket=BUCKET, Key=filename, Body=body["content"].encode("utf-8"))
    except (ClientError, BotoCoreError) as e:
        logging.error(e)
        return jsonify({"error": str(e)}), 500
    return jsonify({"status": "ok", "message": f"'{filename}' saved"})


@app.route("/export/<path:filename>", methods=["GET"])
def export_object(filename):
    try:
        s3 = storage_client()
        obj = s3.get_object(Bucket=BUCKET, Key=filename)
        raw = obj["Body"].read()
    except (ClientError, BotoCoreError) as e:
        logging.error(e)
        return jsonify({"error": str(e)}), 500
    return send_file(
        io.BytesIO(raw),
        download_name=filename,
        as_attachment=True,
        mimetype="text/markdown",
    )


@app.route("/store", methods=["POST"])
def store_file():
    if "file" not in request.files:
        return jsonify({"error": "No file provided"}), 400

    file = request.files["file"]

    if file.filename == "":
        return jsonify({"error": "Empty filename"}), 400

    if not file.filename.endswith(".md"):
        return jsonify({"error": "Only .md files are accepted"}), 400

    content = file.read()
    file_size = len(content)

    try:
        s3 = storage_client()
        s3.upload_fileobj(io.BytesIO(content), BUCKET, file.filename)
    except (ClientError, BotoCoreError) as e:
        logging.error(e)
        return jsonify({"error": str(e)}), 500

    try:
        requests.post(
            f"{HISTORY_SERVICE_URL}/records",
            json={"name": file.filename, "size": file_size},
            timeout=5,
        )
    except requests.RequestException as e:
        logging.error(f"history-service call failed: {e}")

    return jsonify({"status": "ok", "message": f"'{file.filename}' stored successfully"})


@app.route("/history", methods=["GET"])
def get_history():
    try:
        resp = requests.get(f"{HISTORY_SERVICE_URL}/records", timeout=5)
        resp.raise_for_status()
    except requests.RequestException as e:
        logging.error(f"history-service call failed: {e}")
        return jsonify({"error": str(e)}), 502
    return jsonify(resp.json())


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
