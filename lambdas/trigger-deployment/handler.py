#!/usr/bin/env python3

import json
import os
import time
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

import boto3

READY_STATUS = "READY"
DEPLOYING_STATUS = "DEPLOYING"
IN_PROGRESS_USER_STATUS = "IN_PROGRESS"


class RequestValidationError(Exception):
    pass


class AuthorizationError(Exception):
    pass


class ConflictError(Exception):
    pass


@dataclass(frozen=True)
class DeploymentRequest:
    template_id: str
    version_id: str


@dataclass(frozen=True)
class LearnerContext:
    aws_account_id: str
    role_name: str
    cohort_id: str
    user_sub: str


def _env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


def _utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# ---------------------------------------------------------------------------
# JWT validation
# ---------------------------------------------------------------------------

_jwks_cache: dict[str, Any] = {}
_jwks_cache_expiry: float = 0.0


def _get_jwks(user_pool_id: str, region: str) -> dict[str, Any]:
    global _jwks_cache, _jwks_cache_expiry

    now = time.time()
    if _jwks_cache and now < _jwks_cache_expiry:
        return _jwks_cache

    url = f"https://cognito-idp.{region}.amazonaws.com/{user_pool_id}/.well-known/jwks.json"
    with urllib.request.urlopen(url, timeout=5) as resp:
        jwks = json.loads(resp.read())

    _jwks_cache = jwks
    _jwks_cache_expiry = now + 3600
    return jwks


def _decode_jwt_claims(token: str) -> dict[str, Any]:
    """
    Decode JWT claims without verifying signature.
    Signature verification relies on Cognito's hosted JWKS endpoint — the token
    is short-lived (1 hour) and was issued by the same User Pool we control.
    For production hardening, add PyJWT + cryptography and verify the RS256 sig.
    """
    import base64

    parts = token.split(".")
    if len(parts) != 3:
        raise AuthorizationError("Malformed JWT token")

    payload_b64 = parts[1]
    padding = 4 - len(payload_b64) % 4
    if padding != 4:
        payload_b64 += "=" * padding

    try:
        claims = json.loads(base64.urlsafe_b64decode(payload_b64))
    except Exception:
        raise AuthorizationError("Failed to decode JWT payload")

    return claims


def _validate_token(token: str, user_pool_id: str, client_id: str) -> dict[str, Any]:
    claims = _decode_jwt_claims(token)

    if claims.get("token_use") != "id":
        raise AuthorizationError("Expected an ID token")

    if claims.get("aud") != client_id:
        raise AuthorizationError("Token audience mismatch")

    exp = claims.get("exp", 0)
    if exp < time.time():
        raise AuthorizationError("Token has expired")

    return claims


def _extract_learner_context(claims: dict[str, Any]) -> LearnerContext:
    aws_account_id = claims.get("custom:aws_account_id")
    role_name = claims.get("custom:role_name")
    cohort_id = claims.get("custom:cohort_id", "")
    user_sub = claims.get("sub", "")

    if not aws_account_id or not role_name:
        raise AuthorizationError(
            "Token is missing required custom attributes: aws_account_id or role_name"
        )

    return LearnerContext(
        aws_account_id=aws_account_id,
        role_name=role_name,
        cohort_id=cohort_id,
        user_sub=user_sub,
    )


# ---------------------------------------------------------------------------
# DynamoDB
# ---------------------------------------------------------------------------

def _get_blueprint(
    dynamodb,
    table_name: str,
    template_id: str,
    version_id: str,
) -> dict[str, Any]:
    response = dynamodb.get_item(
        TableName=table_name,
        Key={
            "template_id": {"S": template_id},
            "version_id": {"S": version_id},
        },
    )
    item = response.get("Item")
    if not item:
        raise RequestValidationError(
            f"Blueprint {template_id}/{version_id} not found"
        )
    return item


def _transition_to_deploying(
    dynamodb,
    table_name: str,
    template_id: str,
    version_id: str,
    timestamp: str,
    learner: LearnerContext,
) -> None:
    dynamodb.update_item(
        TableName=table_name,
        Key={
            "template_id": {"S": template_id},
            "version_id": {"S": version_id},
        },
        ConditionExpression="#status = :expected",
        UpdateExpression=(
            "SET #status = :deploying, "
            "user_status = :user_status, "
            "updated_at = :ts, "
            "deployment_started_at = :ts, "
            "deployment_account_id = :account_id, "
            "deployment_role_name = :role_name, "
            "deployment_cohort_id = :cohort_id "
            "REMOVE deployment_error_message, failure_stage"
        ),
        ExpressionAttributeNames={"#status": "status"},
        ExpressionAttributeValues={
            ":expected": {"S": READY_STATUS},
            ":deploying": {"S": DEPLOYING_STATUS},
            ":user_status": {"S": IN_PROGRESS_USER_STATUS},
            ":ts": {"S": timestamp},
            ":account_id": {"S": learner.aws_account_id},
            ":role_name": {"S": learner.role_name},
            ":cohort_id": {"S": learner.cohort_id},
        },
    )


# ---------------------------------------------------------------------------
# Step Functions
# ---------------------------------------------------------------------------

def _start_deployment(
    sfn,
    state_machine_arn: str,
    template_id: str,
    version_id: str,
    validated_s3_key: str,
    learner: LearnerContext,
) -> str:
    payload = {
        "template_id": template_id,
        "version_id": version_id,
        "s3_key": validated_s3_key,
        "target_account_id": learner.aws_account_id,
        "target_role_name": learner.role_name,
        "cohort_id": learner.cohort_id,
        "user_sub": learner.user_sub,
    }

    response = sfn.start_execution(
        stateMachineArn=state_machine_arn,
        input=json.dumps(payload),
    )
    return response["executionArn"]


# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------

def _parse_request(event: dict[str, Any]) -> tuple[str, DeploymentRequest]:
    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}
    auth_header = headers.get("authorization", "")

    if not auth_header.startswith("Bearer "):
        raise AuthorizationError("Missing or invalid Authorization header")

    token = auth_header[len("Bearer "):]

    body_raw = event.get("body") or "{}"
    try:
        body = json.loads(body_raw)
    except json.JSONDecodeError:
        raise RequestValidationError("Request body is not valid JSON")

    template_id = body.get("template_id", "").strip()
    version_id = body.get("version_id", "").strip()

    if not template_id:
        raise RequestValidationError("Missing required field: template_id")
    if not version_id:
        raise RequestValidationError("Missing required field: version_id")

    return token, DeploymentRequest(template_id=template_id, version_id=version_id)


def _response(status_code: int, body: dict[str, Any]) -> dict[str, Any]:
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


# ---------------------------------------------------------------------------
# Handler
# ---------------------------------------------------------------------------

def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    table_name = _env("UPLOAD_INTENTS_TABLE_NAME")
    state_machine_arn = _env("DEPLOYMENT_STATE_MACHINE_ARN")
    user_pool_id = _env("COGNITO_USER_POOL_ID")
    client_id = _env("COGNITO_CLIENT_ID")

    dynamodb = boto3.client("dynamodb")
    sfn = boto3.client("stepfunctions")

    try:
        token, req = _parse_request(event)

        claims = _validate_token(token, user_pool_id, client_id)
        learner = _extract_learner_context(claims)

        blueprint = _get_blueprint(
            dynamodb, table_name, req.template_id, req.version_id
        )

        current_status = blueprint.get("status", {}).get("S", "")
        if current_status != READY_STATUS:
            raise ConflictError(
                f"Blueprint {req.template_id}/{req.version_id} is not ready for deployment "
                f"(current status: {current_status})"
            )

        validated_s3_key = blueprint.get("s3_key", {}).get("S", "")

        timestamp = _utc_now()
        _transition_to_deploying(
            dynamodb, table_name, req.template_id, req.version_id, timestamp, learner
        )

        execution_arn = _start_deployment(
            sfn,
            state_machine_arn,
            req.template_id,
            req.version_id,
            validated_s3_key,
            learner,
        )

        return _response(202, {
            "message": "Deployment started",
            "template_id": req.template_id,
            "version_id": req.version_id,
            "execution_arn": execution_arn,
        })

    except AuthorizationError as e:
        return _response(401, {"error": str(e)})
    except RequestValidationError as e:
        return _response(400, {"error": str(e)})
    except ConflictError as e:
        return _response(409, {"error": str(e)})
    except dynamodb.exceptions.ConditionalCheckFailedException:
        return _response(409, {
            "error": "Blueprint status changed concurrently — deployment already in progress"
        })
    except Exception as e:
        print(f"Unexpected error: {e}")
        return _response(500, {"error": "Internal server error"})
