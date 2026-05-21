import contextlib
import io
import importlib.util
import json
import os
import pathlib
import sys
import types
import unittest
from unittest.mock import Mock

HANDLER_PATH = pathlib.Path(__file__).resolve().parents[1] / "handler.py"
HANDLER_SPEC = importlib.util.spec_from_file_location(
    "complete_upload_handler",
    HANDLER_PATH,
)
handler = importlib.util.module_from_spec(HANDLER_SPEC)
sys.modules[HANDLER_SPEC.name] = handler
assert HANDLER_SPEC.loader is not None
HANDLER_SPEC.loader.exec_module(handler)

RequestValidationError = handler.RequestValidationError
UploadIntentNotFoundError = handler.UploadIntentNotFoundError
UploadStateConflictError = handler.UploadStateConflictError
UploadVerificationError = handler.UploadVerificationError
_assert_pending_upload = handler._assert_pending_upload
_assert_uploaded_object_matches = handler._assert_uploaded_object_matches
_load_upload_intent = handler._load_upload_intent
_log_event = handler._log_event
_mark_upload_completed = handler._mark_upload_completed
_parse_event_body = handler._parse_event_body
_validate_request = handler._validate_request
build_success_response = handler.build_success_response
format_file_size = handler.format_file_size
lambda_handler = handler.lambda_handler


class CompleteUploadTests(unittest.TestCase):
    def test_parse_event_body_accepts_json_string(self) -> None:
        payload = {"template_id": "tpl_abc", "version_id": "ver_def"}
        event = {"body": json.dumps(payload)}

        result = _parse_event_body(event)

        self.assertEqual(result, payload)

    def test_validate_request_accepts_valid_payload(self) -> None:
        template_id, version_id = _validate_request(
            {"template_id": "tpl_abc", "version_id": "ver_def"}
        )

        self.assertEqual(template_id, "tpl_abc")
        self.assertEqual(version_id, "ver_def")

    def test_validate_request_rejects_missing_template_id(self) -> None:
        with self.assertRaises(RequestValidationError):
            _validate_request({"version_id": "ver_def"})

    def test_assert_pending_upload_rejects_non_pending_status(self) -> None:
        with self.assertRaises(UploadStateConflictError):
            _assert_pending_upload({"status": "UPLOADED"})

    def test_assert_uploaded_object_matches_rejects_size_mismatch(self) -> None:
        with self.assertRaises(UploadVerificationError):
            _assert_uploaded_object_matches(
                {"expected_size_bytes": 42},
                {"ContentLength": 41},
            )

    def test_load_upload_intent_raises_not_found_when_item_missing(self) -> None:
        mock_table = Mock()
        mock_table.get_item.return_value = {}
        fake_boto3 = types.SimpleNamespace(
            resource=Mock(return_value=types.SimpleNamespace(Table=Mock(return_value=mock_table)))
        )

        with unittest.mock.patch.dict(sys.modules, {"boto3": fake_boto3}):
            with self.assertRaises(UploadIntentNotFoundError):
                _load_upload_intent("upload-intents", "tpl_abc", "ver_def")

    def test_format_file_size_returns_human_readable_value(self) -> None:
        self.assertEqual(format_file_size(24576), "24 KB")

    def test_build_success_response_matches_contract_shape(self) -> None:
        result = build_success_response(
            {
                "template_id": "tpl_abc",
                "version_id": "ver_def",
                "s3_bucket": "upload-bucket",
                "s3_key": "blueprints/pending/network-fundamentals/tpl_abc/ver_def/network.zip",
                "template_name": "network fundamentals",
                "file_name": "network.zip",
            },
            {
                "ContentLength": 24576,
            },
        )

        self.assertEqual(result["status"], "UPLOADED")
        self.assertEqual(result["user_status"], "IN_PROGRESS")
        self.assertEqual(result["template"]["name"], "network fundamentals")
        self.assertEqual(result["template"]["file_name"], "network.zip")
        self.assertEqual(result["template"]["status_label"], "In progress")
        self.assertEqual(result["template"]["user_status"], "IN_PROGRESS")
        self.assertEqual(result["template"]["user_status_label"], "In progress")
        self.assertEqual(result["template"]["size_label"], "24 KB")
        self.assertEqual(result["object"]["bucket"], "upload-bucket")
        self.assertEqual(
            result["object"]["key"],
            "blueprints/pending/network-fundamentals/tpl_abc/ver_def/network.zip",
        )
        self.assertEqual(result["object"]["size"], 24576)

    def test_mark_upload_completed_writes_byte_sized_fields(self) -> None:
        mock_table = Mock()
        fake_boto3 = types.SimpleNamespace(
            resource=Mock(return_value=types.SimpleNamespace(Table=Mock(return_value=mock_table)))
        )
        fake_botocore_exceptions = types.SimpleNamespace(ClientError=Exception)

        with unittest.mock.patch.dict(
            sys.modules,
            {
                "boto3": fake_boto3,
                "botocore": types.SimpleNamespace(exceptions=fake_botocore_exceptions),
                "botocore.exceptions": fake_botocore_exceptions,
            },
        ):
            _mark_upload_completed(
                "upload-intents",
                {
                    "template_id": "tpl_abc",
                    "version_id": "ver_def",
                    "expected_size": 1123,
                },
                {
                    "ContentLength": 1123,
                    "ETag": '"etag"',
                },
            )

        update_kwargs = mock_table.update_item.call_args.kwargs
        self.assertIn("expected_size_bytes = :expected_size_bytes", update_kwargs["UpdateExpression"])
        self.assertIn("actual_size_bytes = :actual_size_bytes", update_kwargs["UpdateExpression"])
        self.assertEqual(update_kwargs["ExpressionAttributeValues"][":expected_size_bytes"], 1123)
        self.assertEqual(update_kwargs["ExpressionAttributeValues"][":actual_size_bytes"], 1123)

    def test_lambda_handler_returns_404_when_intent_missing(self) -> None:
        event = {"body": json.dumps({"template_id": "tpl_abc", "version_id": "ver_def"})}

        with unittest.mock.patch.dict(
            os.environ,
            {"UPLOAD_INTENTS_TABLE_NAME": "upload-intents"},
            clear=True,
        ), unittest.mock.patch(
            "complete_upload_handler._load_upload_intent",
            side_effect=UploadIntentNotFoundError("Upload intent was not found."),
        ):
            result = lambda_handler(event, None)

        self.assertEqual(result["statusCode"], 404)

    def test_lambda_handler_returns_409_when_status_is_not_pending(self) -> None:
        event = {"body": json.dumps({"template_id": "tpl_abc", "version_id": "ver_def"})}

        with unittest.mock.patch.dict(
            os.environ,
            {"UPLOAD_INTENTS_TABLE_NAME": "upload-intents"},
            clear=True,
        ), unittest.mock.patch(
            "complete_upload_handler._load_upload_intent",
            return_value={"status": "UPLOADED"},
        ):
            result = lambda_handler(event, None)

        self.assertEqual(result["statusCode"], 409)

    def test_lambda_handler_returns_422_when_object_verification_fails(self) -> None:
        event = {"body": json.dumps({"template_id": "tpl_abc", "version_id": "ver_def"})}
        item = {
            "template_id": "tpl_abc",
            "version_id": "ver_def",
            "status": "WAITING_FOR_UPLOAD",
            "expected_size_bytes": 1123,
            "s3_bucket": "upload-bucket",
            "s3_key": "blueprints/pending/network-fundamentals/tpl_abc/ver_def/network.zip",
        }

        with unittest.mock.patch.dict(
            os.environ,
            {"UPLOAD_INTENTS_TABLE_NAME": "upload-intents"},
            clear=True,
        ), unittest.mock.patch(
            "complete_upload_handler._load_upload_intent",
            return_value=item,
        ), unittest.mock.patch(
            "complete_upload_handler._head_uploaded_object",
            side_effect=UploadVerificationError("Uploaded object was not found in S3."),
        ):
            result = lambda_handler(event, None)

        self.assertEqual(result["statusCode"], 422)

    def test_lambda_handler_returns_200_when_completion_succeeds(self) -> None:
        event = {"body": json.dumps({"template_id": "tpl_abc", "version_id": "ver_def"})}
        item = {
            "template_id": "tpl_abc",
            "version_id": "ver_def",
            "status": "WAITING_FOR_UPLOAD",
            "expected_size_bytes": 1123,
            "s3_bucket": "upload-bucket",
            "s3_key": "blueprints/pending/network-fundamentals/tpl_abc/ver_def/network.zip",
        }
        object_metadata = {
            "ContentLength": 1123,
            "ETag": '"etag"',
        }

        with unittest.mock.patch.dict(
            os.environ,
            {"UPLOAD_INTENTS_TABLE_NAME": "upload-intents"},
            clear=True,
        ), unittest.mock.patch(
            "complete_upload_handler._load_upload_intent",
            return_value=item,
        ), unittest.mock.patch(
            "complete_upload_handler._head_uploaded_object",
            return_value=object_metadata,
        ), unittest.mock.patch(
            "complete_upload_handler._mark_upload_completed",
        ):
            result = lambda_handler(event, None)

        self.assertEqual(result["statusCode"], 200)
        body = json.loads(result["body"])
        self.assertEqual(body["status"], "UPLOADED")
        self.assertEqual(body["user_status"], "IN_PROGRESS")

    def test_log_event_writes_structured_json_for_status_transition(self) -> None:
        output = io.StringIO()

        with contextlib.redirect_stdout(output):
            _log_event(
                "INFO",
                "upload.complete.status_transitioned",
                service="complete-upload",
                template_id="tpl_abc",
                version_id="ver_def",
                from_status="WAITING_FOR_UPLOAD",
                to_status="UPLOADED",
            )

        record = json.loads(output.getvalue())
        self.assertEqual(record["level"], "INFO")
        self.assertEqual(record["event"], "upload.complete.status_transitioned")
        self.assertEqual(record["service"], "complete-upload")
        self.assertEqual(record["template_id"], "tpl_abc")
        self.assertEqual(record["version_id"], "ver_def")


if __name__ == "__main__":
    unittest.main()
