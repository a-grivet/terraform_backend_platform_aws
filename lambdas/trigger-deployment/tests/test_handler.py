import base64
import importlib.util
import json
import pathlib
import sys
import time
import types
import unittest
from unittest.mock import MagicMock, patch

# Inject a fake boto3 before loading the handler so the module-level import succeeds.
_fake_boto3 = types.SimpleNamespace(client=MagicMock())
sys.modules.setdefault("boto3", _fake_boto3)

HANDLER_PATH = pathlib.Path(__file__).resolve().parents[1] / "handler.py"
HANDLER_SPEC = importlib.util.spec_from_file_location("trigger_deployment_handler", HANDLER_PATH)
handler_module = importlib.util.module_from_spec(HANDLER_SPEC)
sys.modules[HANDLER_SPEC.name] = handler_module
HANDLER_SPEC.loader.exec_module(handler_module)

AuthorizationError = handler_module.AuthorizationError
ConflictError = handler_module.ConflictError
RequestValidationError = handler_module.RequestValidationError
LearnerContext = handler_module.LearnerContext
_decode_jwt_claims = handler_module._decode_jwt_claims
_extract_learner_context = handler_module._extract_learner_context
_parse_request = handler_module._parse_request
_validate_token = handler_module._validate_token
handler = handler_module.handler


def _make_jwt(claims: dict, expired: bool = False) -> str:
    header = base64.urlsafe_b64encode(
        json.dumps({"alg": "RS256", "typ": "JWT"}).encode()
    ).rstrip(b"=").decode()

    exp_claims = {**claims, "exp": int(time.time()) - 3600 if expired else int(time.time()) + 3600}
    payload = base64.urlsafe_b64encode(
        json.dumps(exp_claims).encode()
    ).rstrip(b"=").decode()

    return f"{header}.{payload}.fakesig"


VALID_CLAIMS = {
    "sub": "user-uuid-001",
    "token_use": "id",
    "aud": "test-client-id",
    "custom:aws_account_id": "066122607629",
    "custom:role_name": "inca-learner-sandbox-001",
    "custom:cohort_id": "cohort-2026-test",
}

ENV = {
    "UPLOAD_INTENTS_TABLE_NAME": "inca-upload-intents-dev",
    "DEPLOYMENT_STATE_MACHINE_ARN": "arn:aws:states:eu-west-3:066122607629:stateMachine:inca-deployment-dev",
    "COGNITO_USER_POOL_ID": "eu-west-3_TEST",
    "COGNITO_CLIENT_ID": "test-client-id",
}


class TestDecodeJwtClaims(unittest.TestCase):
    def test_valid_token(self):
        token = _make_jwt(VALID_CLAIMS)
        claims = _decode_jwt_claims(token)
        self.assertEqual(claims["sub"], "user-uuid-001")

    def test_malformed_token_too_many_parts(self):
        with self.assertRaises(AuthorizationError):
            _decode_jwt_claims("not.a.valid.jwt.with.too.many.parts")

    def test_single_part_token(self):
        with self.assertRaises(AuthorizationError):
            _decode_jwt_claims("onlyonepart")


class TestValidateToken(unittest.TestCase):
    def test_valid_token(self):
        token = _make_jwt(VALID_CLAIMS)
        claims = _validate_token(token, "eu-west-3_ABC", "test-client-id")
        self.assertEqual(claims["sub"], "user-uuid-001")

    def test_wrong_token_use(self):
        token = _make_jwt({**VALID_CLAIMS, "token_use": "access"})
        with self.assertRaises(AuthorizationError):
            _validate_token(token, "eu-west-3_ABC", "test-client-id")

    def test_wrong_audience(self):
        token = _make_jwt(VALID_CLAIMS)
        with self.assertRaises(AuthorizationError):
            _validate_token(token, "eu-west-3_ABC", "wrong-client-id")

    def test_expired_token(self):
        token = _make_jwt(VALID_CLAIMS, expired=True)
        with self.assertRaises(AuthorizationError):
            _validate_token(token, "eu-west-3_ABC", "test-client-id")


class TestExtractLearnerContext(unittest.TestCase):
    def test_valid_claims(self):
        learner = _extract_learner_context(VALID_CLAIMS)
        self.assertEqual(learner.aws_account_id, "066122607629")
        self.assertEqual(learner.role_name, "inca-learner-sandbox-001")
        self.assertEqual(learner.cohort_id, "cohort-2026-test")

    def test_missing_account_id(self):
        claims = {k: v for k, v in VALID_CLAIMS.items() if k != "custom:aws_account_id"}
        with self.assertRaises(AuthorizationError):
            _extract_learner_context(claims)

    def test_missing_role_name(self):
        claims = {k: v for k, v in VALID_CLAIMS.items() if k != "custom:role_name"}
        with self.assertRaises(AuthorizationError):
            _extract_learner_context(claims)


class TestParseRequest(unittest.TestCase):
    def _event(self, body: dict, token: str = None) -> dict:
        tok = token or _make_jwt(VALID_CLAIMS)
        return {"headers": {"Authorization": f"Bearer {tok}"}, "body": json.dumps(body)}

    def test_valid_request(self):
        tok, req = _parse_request(self._event({"template_id": "vpc-lab", "version_id": "v1"}))
        self.assertEqual(req.template_id, "vpc-lab")
        self.assertEqual(req.version_id, "v1")

    def test_missing_auth_header(self):
        with self.assertRaises(AuthorizationError):
            _parse_request({"headers": {}, "body": json.dumps({"template_id": "x", "version_id": "y"})})

    def test_missing_template_id(self):
        with self.assertRaises(RequestValidationError):
            _parse_request(self._event({"version_id": "v1"}))

    def test_missing_version_id(self):
        with self.assertRaises(RequestValidationError):
            _parse_request(self._event({"template_id": "vpc-lab"}))

    def test_invalid_json_body(self):
        tok = _make_jwt(VALID_CLAIMS)
        with self.assertRaises(RequestValidationError):
            _parse_request({"headers": {"Authorization": f"Bearer {tok}"}, "body": "not-json"})


class TestHandler(unittest.TestCase):
    def _event(self, body: dict = None) -> dict:
        token = _make_jwt(VALID_CLAIMS)
        return {
            "headers": {"Authorization": f"Bearer {token}"},
            "body": json.dumps(body or {"template_id": "vpc-lab", "version_id": "v1"}),
        }

    def _mock_dynamodb(self, status: str = "READY") -> MagicMock:
        mock = MagicMock()
        mock.get_item.return_value = {
            "Item": {
                "template_id": {"S": "vpc-lab"},
                "version_id": {"S": "v1"},
                "status": {"S": status},
                "s3_key": {"S": "blueprints/validated/vpc-lab/v1/package.zip"},
            }
        }
        mock.exceptions.ConditionalCheckFailedException = Exception
        return mock

    def _mock_sfn(self) -> MagicMock:
        mock = MagicMock()
        mock.start_execution.return_value = {"executionArn": "arn:aws:states:::execution/test"}
        return mock

    @patch.dict("os.environ", ENV)
    @patch.object(handler_module, "boto3")
    def test_successful_deployment(self, mock_boto3):
        mock_ddb = self._mock_dynamodb()
        mock_boto3.client.side_effect = lambda svc: mock_ddb if svc == "dynamodb" else self._mock_sfn()

        response = handler(self._event(), None)

        self.assertEqual(response["statusCode"], 202)
        body = json.loads(response["body"])
        self.assertEqual(body["template_id"], "vpc-lab")
        mock_ddb.update_item.assert_called_once()

    @patch.dict("os.environ", ENV)
    @patch.object(handler_module, "boto3")
    def test_blueprint_not_ready_returns_409(self, mock_boto3):
        mock_ddb = self._mock_dynamodb(status="VALIDATING")
        mock_boto3.client.side_effect = lambda svc: mock_ddb if svc == "dynamodb" else self._mock_sfn()

        response = handler(self._event(), None)

        self.assertEqual(response["statusCode"], 409)

    @patch.dict("os.environ", ENV)
    @patch.object(handler_module, "boto3")
    def test_missing_auth_returns_401(self, mock_boto3):
        mock_boto3.client.return_value = MagicMock()
        response = handler({"headers": {}, "body": json.dumps({"template_id": "x", "version_id": "y"})}, None)
        self.assertEqual(response["statusCode"], 401)

    @patch.dict("os.environ", ENV)
    @patch.object(handler_module, "boto3")
    def test_blueprint_not_found_returns_400(self, mock_boto3):
        mock_ddb = MagicMock()
        mock_ddb.get_item.return_value = {"Item": None}
        mock_ddb.exceptions.ConditionalCheckFailedException = Exception
        mock_boto3.client.side_effect = lambda svc: mock_ddb if svc == "dynamodb" else self._mock_sfn()

        response = handler(self._event(), None)

        self.assertEqual(response["statusCode"], 400)


if __name__ == "__main__":
    unittest.main()
