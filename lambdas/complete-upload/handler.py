#!/usr/bin/env python3

import json
import os
import time
import uuid
from datetime import datetime, timezone
from typing import Any


class RequestValidationError(Exception):
    pass


class UploadIntentNotFoundError(Exception):
    pass


class UploadStateConflictError(Exception):
    pass


class UploadVerificationError(Exception):
    pass


WAITING_FOR_UPLOAD_STATUS = "WAITING_FOR_UPLOAD"
UPLOADED_STATUS = "UPLOADED"


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
        "service": "complete-upload",
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


def response(status_code: int, body: dict[str, Any]) -> dict[str, Any]:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
        },
        "body": json.dumps(body),
    }


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


def _validate_request(payload: dict[str, Any]) -> tuple[str, str]:
    template_id = payload.get("template_id")
    version_id = payload.get("version_id")

    if not template_id or not isinstance(template_id, str):
        raise RequestValidationError("template_id is required.")

    if not version_id or not isinstance(version_id, str):
        raise RequestValidationError("version_id is required.")

    return template_id.strip(), version_id.strip()


def _load_upload_intent(table_name: str, template_id: str, version_id: str) -> dict[str, Any]:
    import boto3

    dynamodb = boto3.resource("dynamodb")
    table = dynamodb.Table(table_name)
    result = table.get_item(
        Key={
            "template_id": template_id,
            "version_id": version_id,
        }
    )

    item = result.get("Item")
    if not item:
        raise UploadIntentNotFoundError("Upload intent was not found.")

    return item


def _assert_pending_upload(item: dict[str, Any]) -> None:
    if item.get("status") != WAITING_FOR_UPLOAD_STATUS:
        raise UploadStateConflictError("Upload intent is not waiting for upload.")


def _head_uploaded_object(bucket_name: str, s3_key: str) -> dict[str, Any]:
    import boto3
    from botocore.exceptions import ClientError

    s3_client = boto3.client("s3")
    try:
        return s3_client.head_object(Bucket=bucket_name, Key=s3_key)
    except ClientError as exc:
        error_code = exc.response.get("Error", {}).get("Code", "")
        if error_code in {"404", "NoSuchKey", "NotFound"}:
            raise UploadVerificationError("Uploaded object was not found in S3.") from exc
        raise


def _expected_size_bytes(item: dict[str, Any]) -> int | None:
    return item.get("expected_size_bytes", item.get("expected_size"))


def _assert_uploaded_object_matches(item: dict[str, Any], object_metadata: dict[str, Any]) -> None:
    expected_size = _expected_size_bytes(item)
    actual_size = object_metadata.get("ContentLength")

    if actual_size != expected_size:
        raise UploadVerificationError("Uploaded object size does not match expected_size_bytes.")


def _mark_upload_completed(
    table_name: str,
    item: dict[str, Any],
    object_metadata: dict[str, Any],
) -> None:
    import boto3
    from botocore.exceptions import ClientError

    now = _utc_now_iso()
    dynamodb = boto3.resource("dynamodb")
    table = dynamodb.Table(table_name)

    try:
        table.update_item(
            Key={
                "template_id": item["template_id"],
                "version_id": item["version_id"],
            },
            UpdateExpression=(
                "SET #status = :status, "
                "user_status = :user_status, "
                "user_status_label = :user_status_label, "
                "updated_at = :updated_at, "
                "uploaded_at = :uploaded_at, "
                "expected_size_bytes = :expected_size_bytes, "
                "actual_size_bytes = :actual_size_bytes, "
                "etag = :etag"
            ),
            ConditionExpression="#status = :pending_status",
            ExpressionAttributeNames={
                "#status": "status",
            },
            ExpressionAttributeValues={
                ":status": UPLOADED_STATUS,
                ":user_status": user_status(UPLOADED_STATUS),
                ":user_status_label": user_status_label(UPLOADED_STATUS),
                ":pending_status": WAITING_FOR_UPLOAD_STATUS,
                ":updated_at": now,
                ":uploaded_at": now,
                ":expected_size_bytes": _expected_size_bytes(item),
                ":actual_size_bytes": object_metadata["ContentLength"],
                ":etag": object_metadata.get("ETag"),
            },
        )
    except ClientError as exc:
        error_code = exc.response.get("Error", {}).get("Code", "")
        if error_code == "ConditionalCheckFailedException":
            raise UploadStateConflictError("Upload intent is not waiting for upload.") from exc
        raise


def build_success_response(item: dict[str, Any], object_metadata: dict[str, Any]) -> dict[str, Any]:
    actual_size = object_metadata["ContentLength"]
    status = UPLOADED_STATUS

    return {
        "template_id": item["template_id"],
        "version_id": item["version_id"],
        "status": status,
        "user_status": user_status(status),
        "template": {
            "name": item.get("template_name"),
            "file_name": item.get("file_name"),
            "status_label": user_status_label(status),
            "user_status": user_status(status),
            "user_status_label": user_status_label(status),
            "size_bytes": actual_size,
            "size_label": format_file_size(actual_size),
            "last_updated_at": _utc_now_iso(),
        },
        "object": {
            "bucket": item["s3_bucket"],
            "key": item["s3_key"],
            "size": actual_size,
        },
    }


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    started_at = time.monotonic()
    log_context = _request_context(event, context)

    try:
        _log_event("INFO", "upload.complete.started", **log_context)

        table_name = os.environ["UPLOAD_INTENTS_TABLE_NAME"]

        payload = _parse_event_body(event)
        template_id, version_id = _validate_request(payload)
        item = _load_upload_intent(table_name, template_id, version_id)
        _log_event(
            "INFO",
            "upload.complete.intent_loaded",
            **log_context,
            template_id=template_id,
            version_id=version_id,
            current_status=item.get("status"),
            s3_bucket=item.get("s3_bucket"),
            s3_key=item.get("s3_key"),
        )

        _assert_pending_upload(item)

        object_metadata = _head_uploaded_object(
            bucket_name=item["s3_bucket"],
            s3_key=item["s3_key"],
        )
        _assert_uploaded_object_matches(item, object_metadata)
        _log_event(
            "INFO",
            "upload.complete.object_verified",
            **log_context,
            template_id=template_id,
            version_id=version_id,
            expected_size_bytes=_expected_size_bytes(item),
            actual_size_bytes=object_metadata.get("ContentLength"),
            etag=object_metadata.get("ETag"),
        )

        _mark_upload_completed(table_name, item, object_metadata)
        _log_event(
            "INFO",
            "upload.complete.status_transitioned",
            **log_context,
            template_id=template_id,
            version_id=version_id,
            from_status=WAITING_FOR_UPLOAD_STATUS,
            to_status=UPLOADED_STATUS,
        )

        _log_event(
            "INFO",
            "upload.complete.completed",
            **log_context,
            template_id=template_id,
            version_id=version_id,
            status=UPLOADED_STATUS,
            duration_ms=_duration_ms(started_at),
        )

        return response(200, build_success_response(item, object_metadata))
    except RequestValidationError as exc:
        _log_event(
            "WARNING",
            "upload.complete.validation_failed",
            **log_context,
            error_message=str(exc),
            duration_ms=_duration_ms(started_at),
        )
        return response(400, {"message": str(exc)})
    except UploadIntentNotFoundError as exc:
        _log_event(
            "WARNING",
            "upload.complete.intent_not_found",
            **log_context,
            error_message=str(exc),
            duration_ms=_duration_ms(started_at),
        )
        return response(404, {"message": str(exc)})
    except UploadStateConflictError as exc:
        _log_event(
            "WARNING",
            "upload.complete.state_conflict",
            **log_context,
            error_message=str(exc),
            duration_ms=_duration_ms(started_at),
        )
        return response(409, {"message": str(exc)})
    except UploadVerificationError as exc:
        _log_event(
            "WARNING",
            "upload.complete.object_verification_failed",
            **log_context,
            error_message=str(exc),
            duration_ms=_duration_ms(started_at),
        )
        return response(422, {"message": str(exc)})
    except KeyError as exc:
        _log_event(
            "ERROR",
            "upload.complete.configuration_missing",
            **log_context,
            missing_configuration=exc.args[0],
            duration_ms=_duration_ms(started_at),
        )
        return response(500, {"message": f"Missing required configuration: {exc.args[0]}"})
    except Exception as exc:
        _log_event(
            "ERROR",
            "upload.complete.unhandled_error",
            **log_context,
            error_type=type(exc).__name__,
            error_message=str(exc),
            duration_ms=_duration_ms(started_at),
        )
        raise
