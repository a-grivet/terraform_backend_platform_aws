import contextlib
import io
import importlib.util
import json
import os
import pathlib
import sys
import types
import unittest
from unittest.mock import Mock, patch

HANDLER_PATH = pathlib.Path(__file__).resolve().parents[1] / "handler.py"
HANDLER_SPEC = importlib.util.spec_from_file_location(
    "prepare_upload_handler",
    HANDLER_PATH,
)
handler = importlib.util.module_from_spec(HANDLER_SPEC)
sys.modules[HANDLER_SPEC.name] = handler
assert HANDLER_SPEC.loader is not None
HANDLER_SPEC.loader.exec_module(handler)

ACCEPTED_CONTENT_TYPES = handler.ACCEPTED_CONTENT_TYPES
RequestValidationError = handler.RequestValidationError
UploadRequest = handler.UploadRequest
_build_s3_presign_client_config = handler._build_s3_presign_client_config
_generate_opaque_id = handler._generate_opaque_id
_get_upload_bucket_region = handler._get_upload_bucket_region
_log_event = handler._log_event
_parse_event_body = handler._parse_event_body
_presign_upload_url = handler._presign_upload_url
_validate_request = handler._validate_request
build_s3_key = handler.build_s3_key
build_success_response = handler.build_success_response
build_upload_intent_item = handler.build_upload_intent_item
format_file_size = handler.format_file_size
slugify = handler.slugify


class PrepareUploadTests(unittest.TestCase):
    def test_parse_event_body_accepts_json_string(self) -> None:
        payload = {"template_name": "lab", "file_name": "lab.zip", "content_type": "application/zip", "file_size": 1}
        event = {"body": json.dumps(payload)}

        result = _parse_event_body(event)

        self.assertEqual(result, payload)

    def test_validate_request_accepts_valid_payload(self) -> None:
        payload = {
            "template_name": "network fundamentals",
            "file_name": "network.zip",
            "content_type": "application/zip",
            "file_size": 1024,
        }

        result = _validate_request(payload, max_upload_size_bytes=20 * 1024 * 1024)

        self.assertEqual(
            result,
            UploadRequest(
                template_name="network fundamentals",
                file_name="network.zip",
                content_type="application/zip",
                file_size=1024,
            ),
        )

    def test_validate_request_rejects_non_zip_filename(self) -> None:
        payload = {
            "template_name": "network fundamentals",
            "file_name": "network.txt",
            "content_type": "application/zip",
            "file_size": 1024,
        }

        with self.assertRaises(RequestValidationError):
            _validate_request(payload, max_upload_size_bytes=20 * 1024 * 1024)

    def test_validate_request_rejects_unsupported_content_type(self) -> None:
        payload = {
            "template_name": "network fundamentals",
            "file_name": "network.zip",
            "content_type": "text/plain",
            "file_size": 1024,
        }

        with self.assertRaises(RequestValidationError):
            _validate_request(payload, max_upload_size_bytes=20 * 1024 * 1024)

    def test_validate_request_rejects_oversized_upload(self) -> None:
        payload = {
            "template_name": "network fundamentals",
            "file_name": "network.zip",
            "content_type": "application/zip",
            "file_size": 30 * 1024 * 1024,
        }

        with self.assertRaises(RequestValidationError):
            _validate_request(payload, max_upload_size_bytes=20 * 1024 * 1024)

    def test_generate_opaque_id_uses_prefix(self) -> None:
        generated = _generate_opaque_id("tpl")

        self.assertTrue(generated.startswith("tpl_"))
        self.assertGreater(len(generated), 8)

    def test_build_s3_key_uses_backend_controlled_path(self) -> None:
        self.assertEqual(
            build_s3_key(
                "network-fundamentals",
                "tpl_abc",
                "ver_def",
                "network.zip",
            ),
            "blueprints/pending/network-fundamentals/tpl_abc/ver_def/network.zip",
        )

    def test_slugify_normalizes_template_name(self) -> None:
        self.assertEqual(slugify("Network Fundamentals Lab"), "network-fundamentals-lab")

    def test_format_file_size_returns_human_readable_value(self) -> None:
        self.assertEqual(format_file_size(24576), "24 KB")

    def test_build_upload_intent_item_sets_pending_upload(self) -> None:
        request = UploadRequest(
            template_name="network fundamentals",
            file_name="network.zip",
            content_type="application/zip",
            file_size=1024,
        )

        item = build_upload_intent_item(
            request=request,
            bucket_name="test-bucket",
            template_id="tpl_abc",
            version_id="ver_def",
            created_by="trainer-123",
        )

        self.assertEqual(item["status"], "WAITING_FOR_UPLOAD")
        self.assertEqual(item["user_status"], "IN_PROGRESS")
        self.assertEqual(item["user_status_label"], "In progress")
        self.assertEqual(item["template_slug"], "network-fundamentals")
        self.assertEqual(
            item["s3_key"],
            "blueprints/pending/network-fundamentals/tpl_abc/ver_def/network.zip",
        )
        self.assertEqual(item["created_by"], "trainer-123")

    def test_build_success_response_matches_contract_shape(self) -> None:
        item = {
            "template_id": "tpl_abc",
            "version_id": "ver_def",
            "status": "WAITING_FOR_UPLOAD",
            "user_status": "IN_PROGRESS",
            "template_name": "network fundamentals",
            "file_name": "network.zip",
            "expected_size_bytes": 24576,
            "updated_at": "2026-04-21T10:42:00+00:00",
            "content_type": "application/zip",
            "s3_bucket": "test-bucket",
            "s3_key": "blueprints/pending/network-fundamentals/tpl_abc/ver_def/network.zip",
        }

        result = build_success_response(item, "https://example.com/upload", 900)

        self.assertEqual(result["upload"]["method"], "PUT")
        self.assertEqual(result["upload"]["expires_in"], 900)
        self.assertEqual(result["template"]["name"], "network fundamentals")
        self.assertEqual(result["template"]["file_name"], "network.zip")
        self.assertEqual(result["status"], "WAITING_FOR_UPLOAD")
        self.assertEqual(result["user_status"], "IN_PROGRESS")
        self.assertEqual(result["template"]["status_label"], "In progress")
        self.assertEqual(result["template"]["user_status"], "IN_PROGRESS")
        self.assertEqual(result["template"]["user_status_label"], "In progress")
        self.assertEqual(result["template"]["size_label"], "24 KB")
        self.assertEqual(result["object"]["bucket"], "test-bucket")
        self.assertEqual(
            result["object"]["key"],
            "blueprints/pending/network-fundamentals/tpl_abc/ver_def/network.zip",
        )

    def test_accepted_content_types_are_zip_variants(self) -> None:
        self.assertEqual(
            ACCEPTED_CONTENT_TYPES,
            {"application/zip", "application/x-zip-compressed"},
        )

    def test_get_upload_bucket_region_prefers_explicit_env_var(self) -> None:
        with patch.dict(
            os.environ,
            {
                "UPLOAD_BUCKET_REGION": "eu-west-3",
                "AWS_REGION": "us-east-1",
            },
            clear=True,
        ):
            self.assertEqual(_get_upload_bucket_region(), "eu-west-3")

    def test_build_s3_presign_client_config_uses_regional_endpoint(self) -> None:
        result = _build_s3_presign_client_config("eu-west-3")

        self.assertEqual(result["region_name"], "eu-west-3")
        self.assertEqual(result["endpoint_url"], "https://s3.eu-west-3.amazonaws.com")
        self.assertEqual(result["signature_version"], "s3v4")
        self.assertEqual(result["addressing_style"], "virtual")

    def test_presign_upload_url_uses_regionalized_s3_client(self) -> None:
        mock_s3_client = Mock()
        mock_s3_client.generate_presigned_url.return_value = "https://signed.example"

        class FakeConfig:
            def __init__(self, signature_version: str, s3: dict[str, str]) -> None:
                self.signature_version = signature_version
                self.s3 = s3

        fake_boto3 = types.SimpleNamespace(client=Mock(return_value=mock_s3_client))
        fake_botocore_config = types.SimpleNamespace(Config=FakeConfig)

        with patch.dict(
            sys.modules,
            {
                "boto3": fake_boto3,
                "botocore.config": fake_botocore_config,
            },
        ):
            result = _presign_upload_url(
                bucket_name="upload-bucket",
                s3_key="blueprints/pending/network-fundamentals/tpl_abc/ver_def/network.zip",
                content_type="application/zip",
                expiration_seconds=900,
                bucket_region="eu-west-3",
            )

        self.assertEqual(result, "https://signed.example")
        self.assertEqual(fake_boto3.client.call_args.kwargs["region_name"], "eu-west-3")
        self.assertEqual(
            fake_boto3.client.call_args.kwargs["endpoint_url"],
            "https://s3.eu-west-3.amazonaws.com",
        )
        self.assertEqual(
            fake_boto3.client.call_args.kwargs["config"].signature_version,
            "s3v4",
        )
        self.assertEqual(
            fake_boto3.client.call_args.kwargs["config"].s3["addressing_style"],
            "virtual",
        )
        mock_s3_client.generate_presigned_url.assert_called_once()

    def test_log_event_writes_structured_json_without_presigned_url(self) -> None:
        output = io.StringIO()

        with contextlib.redirect_stdout(output):
            _log_event(
                "INFO",
                "upload.prepare.presigned_url_created",
                service="prepare-upload",
                template_id="tpl_abc",
                expires_in=900,
                method="PUT",
            )

        record = json.loads(output.getvalue())
        self.assertEqual(record["level"], "INFO")
        self.assertEqual(record["event"], "upload.prepare.presigned_url_created")
        self.assertEqual(record["service"], "prepare-upload")
        self.assertEqual(record["template_id"], "tpl_abc")
        self.assertNotIn("url", record)


if __name__ == "__main__":
    unittest.main()
