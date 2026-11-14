import asyncio
import json
import tempfile
import unittest
from io import BytesIO
from pathlib import Path
from unittest.mock import patch

import httpx
from fastapi import HTTPException, UploadFile
from PIL import Image

import app as skinai_api
import backend.ai_service as ai_service
import backend.medical_records as medical_records
from backend.firebase_auth import require_firebase_user


def png_image() -> bytes:
    buffer = BytesIO()
    Image.new("RGBA", (16, 16), color=(10, 20, 30, 128)).save(
        buffer,
        format="PNG",
    )
    return buffer.getvalue()


class ScanSkinServiceTests(unittest.TestCase):
    def setUp(self) -> None:
        skinai_api.app.dependency_overrides[require_firebase_user] = (
            lambda: {"uid": "test-user"}
        )

    def tearDown(self) -> None:
        skinai_api.app.dependency_overrides.clear()

    def test_health_is_public_and_identifies_mock_mode(self) -> None:
        async def request_health() -> httpx.Response:
            transport = httpx.ASGITransport(app=skinai_api.app)
            async with httpx.AsyncClient(
                transport=transport,
                base_url="http://test",
            ) as client:
                return await client.get("/health")

        with patch.dict("os.environ", {"MOCK_API": "1"}):
            response = asyncio.run(request_health())

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()["mock_mode"])

    def test_analyze_requires_firebase_authentication(self) -> None:
        async def request_analyze() -> httpx.Response:
            transport = httpx.ASGITransport(app=skinai_api.app)
            async with httpx.AsyncClient(
                transport=transport,
                base_url="http://test",
            ) as client:
                return await client.post("/analyze")

        skinai_api.app.dependency_overrides.clear()
        response = asyncio.run(request_analyze())

        self.assertEqual(response.status_code, 401)

    def test_mock_response_is_saved_and_does_not_need_provider_key(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            history = Path(directory) / "scan_log.jsonl"
            with patch.dict(
                "os.environ",
                {
                    "MOCK_API": "1",
                    "SCANSKIN_HISTORY_PATH": str(history),
                    "SCANSKIN_API_KEY": "",
                },
            ):
                response = self._post_analyze(
                    files={"image": ("scan.png", png_image(), "image/png")}
                )
            self.assertEqual(response.status_code, 200)
            result = response.json()
            self.assertEqual(result["result"], "Mock screening result")
            self.assertIn("## Mock analysis", result["summary"])
            self.assertRegex(result["id"], r"^[0-9a-f-]{36}$")
            self.assertTrue(result["timestamp"])
            saved = json.loads(history.read_text(encoding="utf-8").splitlines()[0])
            self.assertEqual(saved, result)

    def test_opted_in_provider_analysis_creates_owner_scoped_record(self):
        image_bytes = png_image()
        transport = httpx.MockTransport(
            lambda _: httpx.Response(
                200,
                json={
                    "result": "Provider result for test",
                    "confidence": 0.62,
                    "summary": "Provider explanation for test.",
                },
            )
        )

        def client_factory():
            return httpx.AsyncClient(
                transport=transport,
                timeout=httpx.Timeout(120.0, connect=10.0),
            )

        with tempfile.TemporaryDirectory() as directory:
            history = Path(directory) / "history.jsonl"
            with (
                patch.dict(
                    "os.environ",
                    {
                        "MOCK_API": "0",
                        "SCANSKIN_API_KEY": "test-provider-key",
                        "SCANSKIN_HISTORY_PATH": str(history),
                    },
                ),
                patch.object(medical_records, "create_analysis_scan") as save_record,
                patch.object(
                    ai_service,
                    "_create_http_client",
                    side_effect=client_factory,
                ),
            ):
                response = self._post_analyze(
                    files={"image": ("original.png", image_bytes, "image/png")},
                    data={
                        "save_history": "true",
                        "image_storage_consent": "true",
                        "skin_illness_location": "left cheek",
                        "symptoms_details": "User-reported itching.",
                    },
                )

        self.assertEqual(response.status_code, 200)
        save_record.assert_called_once()
        args, kwargs = save_record.call_args
        self.assertEqual(args[0], "test-user")
        self.assertEqual(kwargs["original_image"], image_bytes)
        self.assertEqual(kwargs["original_content_type"], "image/png")
        self.assertEqual(kwargs["body_location"], "left cheek")
        self.assertEqual(kwargs["user_notes"], "User-reported itching.")

    def test_mock_result_cannot_be_saved_as_a_medical_record(self):
        response = self._post_analyze(
            files={"image": ("scan.png", png_image(), "image/png")},
            data={"save_history": "true"},
        )
        self.assertEqual(response.status_code, 409)

    def test_original_image_consent_cannot_be_submitted_without_history_opt_in(self):
        response = self._post_analyze(
            files={"image": ("scan.png", png_image(), "image/png")},
            data={"image_storage_consent": "true"},
        )
        self.assertEqual(response.status_code, 400)

    def test_missing_image_returns_400(self) -> None:
        response = self._post_analyze(files=None, data={})

        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()["detail"], "No input image provided.")

    def test_provider_receives_jpeg_and_optional_fields_once(self) -> None:
        observed: dict[str, object] = {}
        mock_response = {
            "result": "A provider label not known to the app",
            "confidence": 0.78,
            "summary": "## Summary\n\n- Markdown is preserved.",
            "discordant": True,
        }

        def responder(request: httpx.Request) -> httpx.Response:
            observed["url"] = str(request.url)
            observed["headers"] = request.headers
            observed["body"] = request.read()
            return httpx.Response(200, json=mock_response)

        transport = httpx.MockTransport(responder)
        def client_factory():
            return httpx.AsyncClient(
                transport=transport,
                timeout=httpx.Timeout(120.0, connect=10.0),
            )

        with tempfile.TemporaryDirectory() as directory:
            history = Path(directory) / "history.jsonl"
            with (
                patch.dict(
                    "os.environ",
                    {
                        "MOCK_API": "0",
                        "SCANSKIN_API_KEY": "server-only-test-key",
                        "SCANSKIN_HISTORY_PATH": str(history),
                    },
                ),
                patch.object(
                    ai_service,
                    "_create_http_client",
                    side_effect=client_factory,
                ),
            ):
                response = self._post_analyze(
                    files={"image": ("scan.png", png_image(), "image/png")},
                    data={
                        "skin_illness_location": "face",
                        "symptoms_duration": "2 weeks",
                        "symptoms_details": "itching",
                        "symptoms_change_over_time": "spreading",
                    },
                )

        result = response.json()
        body = observed["body"]
        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            observed["url"],
            "https://scanskinai.aihealthpred.com/api/detect/",
        )
        self.assertEqual(observed["headers"]["x-api-key"], "server-only-test-key")
        self.assertIn(b'name="input_image"; filename="scan.jpg"', body)
        self.assertIn(b"Content-Type: image/jpeg", body)
        self.assertIn(b"name=\"symptoms_change_over_time\"", body)
        self.assertEqual(result["result"], mock_response["result"])
        self.assertEqual(result["confidence"], 0.78)
        self.assertEqual(result["summary"], mock_response["summary"])
        self.assertNotIn("discordant", result)
        self.assertNotIn("server-only-test-key", response.text)

    def test_upstream_auth_and_timeout_errors_are_mapped(self) -> None:
        cases = [
            (
                httpx.Response(403, json={"error": "Forbidden"}),
                403,
            ),
            (
                httpx.ReadTimeout("timeout"),
                504,
            ),
        ]
        for outcome, expected_status in cases:
            with self.subTest(expected_status=expected_status):
                transport = httpx.MockTransport(
                    lambda _, outcome=outcome: (
                        outcome
                        if isinstance(outcome, httpx.Response)
                        else (_ for _ in ()).throw(outcome)
                    )
                )
                def client_factory():
                    return httpx.AsyncClient(
                        transport=transport,
                        timeout=httpx.Timeout(120.0, connect=10.0),
                    )

                with patch.dict(
                    "os.environ",
                    {"MOCK_API": "0", "SCANSKIN_API_KEY": "test-key"},
                ), patch.object(
                    ai_service,
                    "_create_http_client",
                    side_effect=client_factory,
                ):
                    response = self._post_analyze(
                        files={"image": ("scan.png", png_image(), "image/png")}
                    )
                self.assertEqual(response.status_code, expected_status)

    def test_invalid_provider_payload_returns_502(self) -> None:
        transport = httpx.MockTransport(
            lambda _: httpx.Response(200, json={"result": "missing fields"})
        )
        def client_factory():
            return httpx.AsyncClient(
                transport=transport,
                timeout=httpx.Timeout(120.0, connect=10.0),
            )

        with patch.dict(
            "os.environ",
            {"MOCK_API": "0", "SCANSKIN_API_KEY": "test-key"},
        ), patch.object(
            ai_service,
            "_create_http_client",
            side_effect=client_factory,
        ):
            response = self._post_analyze(
                files={"image": ("scan.png", png_image(), "image/png")}
            )

        self.assertEqual(response.status_code, 502)

    def _post_analyze(
        self,
        *,
        files: dict[str, tuple[str, bytes, str]] | None,
        data: dict[str, str] | None = None,
    ) -> httpx.Response:
        async def send() -> httpx.Response:
            transport = httpx.ASGITransport(app=skinai_api.app)
            async with httpx.AsyncClient(
                transport=transport,
                base_url="http://test",
            ) as client:
                return await client.post(
                    "/analyze",
                    files=files,
                    data=data,
                    headers={"Authorization": "Bearer mocked-token"},
                )

        return asyncio.run(send())


class ImageConversionTests(unittest.TestCase):
    def test_converts_supported_images_to_jpeg(self) -> None:
        result = asyncio.run(
            ai_service._read_and_convert_image(
                UploadFile(
                    filename="image.png",
                    file=BytesIO(png_image()),
                    headers={"content-type": "image/png"},
                )
            )
        )

        with Image.open(BytesIO(result)) as converted:
            self.assertEqual(converted.format, "JPEG")
            self.assertEqual(converted.mode, "RGB")

    def test_rejects_non_image_upload(self) -> None:
        with self.assertRaises(HTTPException) as raised:
            asyncio.run(
                ai_service._read_and_convert_image(
                    UploadFile(filename="scan.jpg", file=BytesIO(b"not an image"))
                )
            )

        self.assertEqual(raised.exception.status_code, 400)

    def test_rejects_mime_type_that_does_not_match_the_image_format(self) -> None:
        with self.assertRaises(HTTPException) as raised:
            asyncio.run(
                ai_service._read_and_convert_image(
                    UploadFile(
                        filename="scan.jpg",
                        file=BytesIO(png_image()),
                        headers={"content-type": "image/jpeg"},
                    )
                )
            )

        self.assertEqual(raised.exception.status_code, 415)


if __name__ == "__main__":
    unittest.main()
