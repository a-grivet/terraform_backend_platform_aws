#!/usr/bin/env python3

import json
import os
import re
import time
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any


DEFAULT_MAX_UPLOAD_SIZE_BYTES = 20 * 1024 * 1024
DEFAULT_PRESIGNED_URL_EXPIRATION_SECONDS = 900
ACCEPTED_CONTENT_TYPES = {
    "application/zip",
    "application/x-zip-compressed",
}
WAITING_FOR_UPLOAD_STATUS = "WAITING_FOR_UPLOAD"
IN_PROGRESS_USER_STATUS = "IN_PROGRESS"


class RequestValidationError(Exception):
    pass


@dataclass(frozen=True)
class UploadRequest:
    template_name: str
    file_name: str
    content_type: str
    file_size: int


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def _duration_ms(started_at: float) -> int:
    return round((time.monotonic() - started_at) * 1000)


def _get_header(event: dict[str, Any], header_name: str) -> str | None:
    headers = event.get("headers") or {}
    header_name_lower = header_name.lower()

    for name, value in headers.items():
        if name.lower() == header_name_lower and value:
            return str(value)

    return None


def _request_context(event: dict[str, Any], context: Any) -> dict[str, Any]:
    request_context = event.get("requestContext", {})
    aws_request_id = getattr(context, "aws_request_id", None)
    api_request_id = request_context.get("requestId")
    correlation_id = (
        _get_header(event, "X-Correlation-Id")
        or api_request_id
        or aws_request_id
        or str(uuid.uuid4())
    )

    return {
        "service": "prepare-upload",
        "correlation_id": correlation_id,
        "aws_request_id": aws_request_id,
        "api_request_id": api_request_id,
        "route_key": event.get("routeKey"),
        "raw_path": event.get("rawPath"),
    }


def _log_event(level: str, event_name: str, **fields: Any) -> None:
    record = {
        "level": level,
        "event": event_name,
        "timestamp": _utc_now_iso(),
    }
    record.update({key: value for key, value in fields.items() if value is not None})
    print(json.dumps(record, sort_keys=True, default=str))


def _generate_opaque_id(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex}"


def slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", value.strip().lower())
    return slug.strip("-") or "template"


def format_file_size(size_bytes: int) -> str:
    if size_bytes < 1024:
        return f"{size_bytes} B"

    size_kb = size_bytes / 1024
    if size_kb < 1024:
        return f"{size_kb:g} KB"

    size_mb = size_kb / 1024
    return f"{size_mb:g} MB"


def user_status(status: str) -> str:
    statuses = {
        "WAITING_FOR_UPLOAD": "IN_PROGRESS",
        "UPLOADED": "IN_PROGRESS",
        "VALIDATING": "IN_PROGRESS",
        "READY": "IN_PROGRESS",
        "VALIDATION_FAILED": "FAILED",
        "DEPLOYING": "DEPLOYING",
        "DEPLOYED": "DEPLOYED",
        "DEPLOY_FAILED": "FAILED",
    }
    return statuses.get(status, status)


def user_status_label(status: str) -> str:
    labels = {
        "WAITING_FOR_UPLOAD": "In progress",
        "UPLOADED": "In progress",
        "VALIDATING": "In progress",
        "READY": "In progress",
        "VALIDATION_FAILED": "Needs changes",
        "DEPLOYING": "Deploying",
        "DEPLOYED": "Deployed",
        "DEPLOY_FAILED": "Deployment failed",
    }
    return labels.get(status, status)


def _parse_event_body(event: dict[str, Any]) -> dict[str, Any]:
    raw_body = event.get("body")
    if raw_body is None:
        raise RequestValidationError("Request body is required.")

    if isinstance(raw_body, dict):
        return raw_body

    try:
        return json.loads(raw_body)
    except json.JSONDecodeError as exc:
        raise RequestValidationError("Request body must be valid JSON.") from exc


def _validate_request(payload: dict[str, Any], max_upload_size_bytes: int) -> UploadRequest:
    template_name = payload.get("template_name")
    file_name = payload.get("file_name")
    content_type = payload.get("content_type")
    file_size = payload.get("file_size")

    if not template_name or not isinstance(template_name, str):
        raise RequestValidationError("template_name is required.")

    if not file_name or not isinstance(file_name, str):
        raise RequestValidationError("file_name is required.")

    if not file_name.endswith(".zip"):
        raise RequestValidationError("file must be in zip format")

    if content_type not in ACCEPTED_CONTENT_TYPES:
        raise RequestValidationError("file content type must be zip")

    if not isinstance(file_size, int):
        raise RequestValidationError("file_size must be an integer.")

    if file_size <= 0:
        raise RequestValidationError("file_size must be greater than 0.")

    if file_size > max_upload_size_bytes:
        max_upload_size_mb = max_upload_size_bytes / (1024 * 1024)
        raise RequestValidationError(
            f"file size must not exceed {max_upload_size_mb:g} MB"
        )

    return UploadRequest(
        template_name=template_name.strip(),
        file_name=file_name,
        content_type=content_type,
        file_size=file_size,
    )


def build_s3_key(
    template_slug: str,
    template_id: str,
    version_id: str,
    file_name: str,
) -> str:
    return f"blueprints/pending/{template_slug}/{template_id}/{version_id}/{file_name}"


def build_upload_intent_item(
    request: UploadRequest,
    bucket_name: str,
    template_id: str,
    version_id: str,
    created_by: str,
) -> dict[str, Any]:
    now = _utc_now_iso()
    template_slug = slugify(request.template_name)
    s3_key = build_s3_key(template_slug, template_id, version_id, request.file_name)

    return {
        "template_id": template_id,
        "version_id": version_id,
        "template_slug": template_slug,
        "template_name": request.template_name,
        "file_name": request.file_name,
        "content_type": request.content_type,
        "expected_size_bytes": request.file_size,
        "s3_bucket": bucket_name,
        "s3_key": s3_key,
        "status": WAITING_FOR_UPLOAD_STATUS,
        "user_status": user_status(WAITING_FOR_UPLOAD_STATUS),
        "user_status_label": user_status_label(WAITING_FOR_UPLOAD_STATUS),
        "created_by": created_by,
        "created_at": now,
        "updated_at": now,
    }


def build_success_response(
    item: dict[str, Any],
    presigned_url: str,
    expiration_seconds: int,
) -> dict[str, Any]:
    return {
        "template_id": item["template_id"],
        "version_id": item["version_id"],
        "status": item["status"],
        "user_status": user_status(item["status"]),
        "template": {
            "name": item["template_name"],
            "file_name": item["file_name"],
            "status_label": user_status_label(item["status"]),
            "user_status": user_status(item["status"]),
            "user_status_label": user_status_label(item["status"]),
            "size_bytes": item["expected_size_bytes"],
            "size_label": format_file_size(item["expected_size_bytes"]),
            "last_updated_at": item["updated_at"],
        },
        "upload": {
            "method": "PUT",
            "url": presigned_url,
            "expires_in": expiration_seconds,
            "headers": {
                "Content-Type": item["content_type"],
            },
        },
        "object": {
            "bucket": item["s3_bucket"],
            "key": item["s3_key"],
        },
    }


def response(status_code: int, body: dict[str, Any]) -> dict[str, Any]:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
        },
        "body": json.dumps(body),
    }


def get_actor_id(event: dict[str, Any]) -> str:
    request_context = event.get("requestContext", {})
    authorizer = request_context.get("authorizer", {})

    for candidate in (
        authorizer.get("principalId"),
        authorizer.get("user_id"),
        request_context.get("accountId"),
    ):
        if candidate:
            return str(candidate)

    return "unknown"


def _put_upload_intent(table_name: str, item: dict[str, Any]) -> None:
    import boto3

    dynamodb = boto3.resource("dynamodb")
    table = dynamodb.Table(table_name)
    table.put_item(Item=item)


def _get_upload_bucket_region() -> str:
    for env_var_name in ("UPLOAD_BUCKET_REGION", "AWS_REGION", "AWS_DEFAULT_REGION"):
        value = os.environ.get(env_var_name)
        if value:
            return value

    return "us-east-1"


def _build_s3_presign_client_config(bucket_region: str) -> dict[str, Any]:
    return {
        "region_name": bucket_region,
        "endpoint_url": f"https://s3.{bucket_region}.amazonaws.com",
        "signature_version": "s3v4",
        "addressing_style": "virtual",
    }


def _presign_upload_url(
    bucket_name: str,
    s3_key: str,
    content_type: str,
    expiration_seconds: int,
    bucket_region: str,
) -> str:
    import boto3
    from botocore.config import Config

    client_config = _build_s3_presign_client_config(bucket_region)
    s3_client = boto3.client(
        "s3",
        region_name=client_config["region_name"],
        endpoint_url=client_config["endpoint_url"],
        config=Config(
            signature_version=client_config["signature_version"],
            s3={"addressing_style": client_config["addressing_style"]},
        ),
    )
    return s3_client.generate_presigned_url(
        "put_object",
        Params={
            "Bucket": bucket_name,
            "Key": s3_key,
            "ContentType": content_type,
        },
        ExpiresIn=expiration_seconds,
        HttpMethod="PUT",
    )


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    started_at = time.monotonic()
    log_context = _request_context(event, context)

    try:
        _log_event("INFO", "upload.prepare.started", **log_context)

        bucket_name = os.environ["UPLOAD_BUCKET_NAME"]
        bucket_region = _get_upload_bucket_region()
        table_name = os.environ["UPLOAD_INTENTS_TABLE_NAME"]
        max_upload_size_bytes = int(
            os.environ.get("MAX_UPLOAD_SIZE_BYTES", str(DEFAULT_MAX_UPLOAD_SIZE_BYTES))
        )
        expiration_seconds = int(
            os.environ.get(
                "PRESIGNED_URL_EXPIRATION_SECONDS",
                str(DEFAULT_PRESIGNED_URL_EXPIRATION_SECONDS),
            )
        )

        payload = _parse_event_body(event)
        upload_request = _validate_request(payload, max_upload_size_bytes)
        _log_event(
            "INFO",
            "upload.prepare.request_validated",
            **log_context,
            template_name=upload_request.template_name,
            file_name=upload_request.file_name,
            content_type=upload_request.content_type,
            expected_size_bytes=upload_request.file_size,
        )

        template_id = _generate_opaque_id("tpl")
        version_id = _generate_opaque_id("ver")
        actor_id = get_actor_id(event)

        item = build_upload_intent_item(
            request=upload_request,
            bucket_name=bucket_name,
            template_id=template_id,
            version_id=version_id,
            created_by=actor_id,
        )
        _put_upload_intent(table_name, item)
        _log_event(
            "INFO",
            "upload.prepare.intent_created",
            **log_context,
            template_id=template_id,
            version_id=version_id,
            template_name=item["template_name"],
            file_name=item["file_name"],
            s3_bucket=item["s3_bucket"],
            s3_key=item["s3_key"],
            status=item["status"],
            actor_id=actor_id,
        )

        presigned_url = _presign_upload_url(
            bucket_name=bucket_name,
            s3_key=item["s3_key"],
            content_type=item["content_type"],
            expiration_seconds=expiration_seconds,
            bucket_region=bucket_region,
        )
        _log_event(
            "INFO",
            "upload.prepare.presigned_url_created",
            **log_context,
            template_id=template_id,
            version_id=version_id,
            expires_in=expiration_seconds,
            method="PUT",
            required_headers=["Content-Type"],
        )

        _log_event(
            "INFO",
            "upload.prepare.completed",
            **log_context,
            template_id=template_id,
            version_id=version_id,
            status=item["status"],
            duration_ms=_duration_ms(started_at),
        )

        return response(
            200,
            build_success_response(item, presigned_url, expiration_seconds),
        )
    except RequestValidationError as exc:
        _log_event(
            "WARNING",
            "upload.prepare.validation_failed",
            **log_context,
            error_message=str(exc),
            duration_ms=_duration_ms(started_at),
        )
        return response(400, {"message": str(exc)})
    except KeyError as exc:
        _log_event(
            "ERROR",
            "upload.prepare.configuration_missing",
            **log_context,
            missing_configuration=exc.args[0],
            duration_ms=_duration_ms(started_at),
        )
        return response(500, {"message": f"Missing required configuration: {exc.args[0]}"})
    except Exception as exc:
        _log_event(
            "ERROR",
            "upload.prepare.unhandled_error",
            **log_context,
            error_type=type(exc).__name__,
            error_message=str(exc),
            duration_ms=_duration_ms(started_at),
        )
        raise
