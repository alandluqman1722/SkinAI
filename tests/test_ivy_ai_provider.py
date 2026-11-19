from __future__ import annotations

import asyncio
import os
import unittest
from unittest.mock import patch

import httpx
from fastapi import HTTPException

import backend.ivy_ai_provider as ivy_provider

_JPEG = b"\xff\xd8\xfftest-jpeg"
_VALID_RESPONSE = {
    "result": "Screening label",
    "confidence": 97,
    "summary": "Provider screening summary.",
}


class IvyAIProviderTests(unittest.TestCase):
    def _call_provider(self, outcome: httpx.Response | Exception):
        seen: dict[str, object] = {}

        def responder(request: httpx.Request) -> httpx.Response:
            seen["url"] = str(request.url)
            seen["headers"] = request.headers
            seen["body"] = request.read()
            if isinstance(outcome, Exception):
                raise outcome
            return outcome

        transport = httpx.MockTransport(responder)
        original_client = ivy_provider.httpx.AsyncClient

        def client_factory(*args, **kwargs):
            return original_client(*args, transport=transport, **kwargs)

        with (
            patch.dict(os.environ, {"IVYAI_API_KEY": "test-ivy-key"}),
            patch.object(
                ivy_provider.httpx,
                "AsyncClient",
                side_effect=client_factory,
            ),
        ):
            result = asyncio.run(ivy_provider.IvyAIProvider().analyze(_JPEG))
        return result, seen

    def _assert_http_error(
        self,
        outcome: httpx.Response | Exception,
        status_code: int,
    ) -> HTTPException:
        with self.assertRaises(HTTPException) as raised:
            self._call_provider(outcome)
        self.assertEqual(raised.exception.status_code, status_code)
        self.assertNotIn("test-ivy-key", raised.exception.detail)
        return raised.exception

    def test_sends_documented_multipart_request_and_normalizes_response(self):
        result, seen = self._call_provider(
            httpx.Response(
                200,
                json={**_VALID_RESPONSE, "unexpected": "ignored"},
            )
        )

        body = seen["body"]
        self.assertEqual(
            seen["url"],
            "https://scanskinai.aihealthpred.com/api/detect/",
        )
        self.assertEqual(seen["headers"]["x-api-key"], "test-ivy-key")
        self.assertIn(b'name="input_image"; filename="scan.jpg"', body)
        self.assertNotIn(b"symptoms_duration", body)
        self.assertEqual(
            result,
            {
                "result": "Screening label",
                "confidence": 97.0,
                "summary": "Provider screening summary.",
            },
        )

    def test_missing_image_and_invalid_image_format_are_rejected(self):
        for content, expected in ((b"", 400), (b"not an image", 415)):
            with self.subTest(expected=expected):
                with self.assertRaises(HTTPException) as raised:
                    asyncio.run(ivy_provider.IvyAIProvider().analyze(content))
                self.assertEqual(raised.exception.status_code, expected)

    def test_missing_api_key_is_reported_without_network_access(self):
        with patch.dict(os.environ, {"IVYAI_API_KEY": ""}):
            with self.assertRaises(HTTPException) as raised:
                asyncio.run(ivy_provider.IvyAIProvider().analyze(_JPEG))
        self.assertEqual(raised.exception.status_code, 503)
        self.assertNotIn("test-ivy-key", raised.exception.detail)

    def test_invalid_key_and_upstream_statuses_are_sanitized(self):
        for upstream, expected in ((400, 400), (403, 503), (429, 429), (500, 502)):
            with self.subTest(upstream=upstream):
                self._assert_http_error(
                    httpx.Response(upstream, json={"message": "private provider data"}),
                    expected,
                )

    def test_connection_and_read_timeouts_are_distinguished(self):
        request = httpx.Request(
            "POST",
            "https://scanskinai.aihealthpred.com/api/detect/",
        )
        for error in (
            httpx.ConnectTimeout("private connection details", request=request),
            httpx.ReadTimeout("private response details", request=request),
        ):
            with self.subTest(error=type(error).__name__):
                self._assert_http_error(error, 504)

    def test_invalid_json_and_missing_or_invalid_fields_are_rejected(self):
        invalid_json = httpx.Response(
            200,
            content=b"not json",
            headers={"content-type": "application/json"},
        )
        self._assert_http_error(invalid_json, 502)
        for payload in (
            {},
            {"result": "label", "confidence": 101, "summary": "summary"},
            {"result": "label", "confidence": True, "summary": "summary"},
        ):
            with self.subTest(payload=payload):
                self._assert_http_error(
                    httpx.Response(200, json=payload),
                    502,
                )
