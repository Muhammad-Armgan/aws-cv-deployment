"""
Lambda function — CV website handler
Bucket and prefix come from environment variables BUCKET and PREFIX.
No credentials are hardcoded; the Lambda execution role provides access.
"""

import os
import json
import time
import base64
import logging
import boto3
from urllib.parse import unquote

# ── AWS client ────────────────────────────────────────────────────────────────
s3 = boto3.client("s3")

# ── Config from environment — no bucket name or prefix in this file ───────────
BUCKET = os.environ["BUCKET"]
PREFIX = os.environ.get("PREFIX", "site/").rstrip("/") + "/"

# ── Logging ───────────────────────────────────────────────────────────────────
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# ── Content type map ──────────────────────────────────────────────────────────
ROUTES = {
    "/":           (PREFIX + "index.html", "text/html; charset=utf-8",  False),
    "/index.html": (PREFIX + "index.html", "text/html; charset=utf-8",  False),
    "/style.css":  (PREFIX + "style.css",  "text/css; charset=utf-8",   False),
    "/cv.pdf":     (PREFIX + "cv.pdf",     "application/pdf",           True),
}


def lambda_handler(event, context):
    start_ms = time.time() * 1000
    raw_path  = unquote(event.get("rawPath", "/") or "/")

    status       = 200
    is_base64    = False
    cache_control = "max-age=60"
    body         = ""
    content_type = "text/html; charset=utf-8"

    if raw_path in ROUTES:
        key, content_type, is_base64 = ROUTES[raw_path]
        try:
            obj  = s3.get_object(Bucket=BUCKET, Key=key)
            data = obj["Body"].read()

            if raw_path in ("/", "/index.html"):
                # Replace placeholder; read as UTF-8 text
                page = data.decode("utf-8")
                body = page.replace(
                    "{{HOSTED_ON}}",
                    f"Lambda — {context.function_name}"
                )
            elif is_base64:
                body = base64.b64encode(data).decode("ascii")
            else:
                body = data.decode("utf-8")

        except s3.exceptions.NoSuchKey:
            status       = 404
            content_type = "text/html; charset=utf-8"
            is_base64    = False
            body = _not_found_page(raw_path)

        except Exception:
            logger.exception("Unexpected error retrieving %s from S3", key)
            status       = 500
            content_type = "text/html; charset=utf-8"
            is_base64    = False
            cache_control = "no-store"
            body = "<html><body><h1>500 Internal Server Error</h1></body></html>"

    else:
        status = 404
        body   = _not_found_page(raw_path)

    elapsed_ms = round(time.time() * 1000 - start_ms, 2)

    # ── structured log line (one JSON object per request) ────────────────────
    logger.info(json.dumps({
        "fn":     context.function_name,
        "path":   raw_path,
        "status": status,
        "ms":     elapsed_ms,
    }))

    return {
        "statusCode": status,
        "headers": {
            "Content-Type":  content_type,
            "Cache-Control": cache_control,
        },
        "body":            body,
        "isBase64Encoded": is_base64,
    }


def _not_found_page(path: str) -> str:
    safe_path = path.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    return (
        "<!DOCTYPE html><html lang='en'><head><meta charset='UTF-8'>"
        "<title>404 Not Found</title></head><body>"
        f"<h1>404 — Not Found</h1><p>The path <code>{safe_path}</code> "
        "does not exist on this server.</p>"
        "</body></html>"
    )
