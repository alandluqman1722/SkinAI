from __future__ import annotations

import json
import logging
import math
import os
import time
from typing import Any

import httpx
from fastapi import HTTPException

from .medical_ai.provider_telemetry import log_provider_call

_IVYAI_URL = "https://scanskinai.aihealthpred.com/api/detect/"
_CONNECT_TIMEOUT = 8.0
_READ_TIMEOUT = 90.0
_WRITE_TIMEOUT = 20.0
_POOL_TIMEOUT = 8.0
_MAX_RESPONSE_BYTES = 2 * 1024 * 1024
_logger = logging.getLogger(__name__)


def validate_ivy_response(payload: object) -> dict[str, object]:
    if not isinstance(payload, dict):
        raise HTTPException(
            status_code=502,
            detail="Ivy AI returned an invalid response.",
        )

    result = payload.get("result")
    confidence = payload.get("confidence")
    summary = payload.get("summary")
    if (
        not isinstance(result, str)
        or not result.strip()
        or len(result) > 500
        or isinstance(confidence, bool)
        or not isinstance(confidence, (int, float))
        or not math.isfinite(confidence)
        or confidence < 0
        or confidence > 100
        or not isinstance(summary, str)
        or not summary.strip()
        or len(summary) > 10000
    ):
        raise HTTPException(
            status_code=502,
            detail="Ivy AI returned an invalid response.",
        )
    return {
        "result": result.strip(),
        "confidence": float(confidence),
        "summary": summary,
    }


class IvyAIProvider:
    async def analyze(
        self,
        image_bytes: bytes,
    ) -> dict[str, object]:
        started_at = time.perf_counter()
        if not image_bytes:
            raise HTTPException(status_code=400, detail="No input image provided.")
        if not image_bytes.startswith(b"\xff\xd8\xff"):
            raise HTTPException(
                status_code=415,
                detail="Ivy AI requests require a valid JPEG image.",
            )

        api_key = os.getenv("IVYAI_API_KEY", "").strip()
        if not api_key:
            log_provider_call(
                provider="Ivy AI",
                stage="skin_analysis",
                status_code=None,
                started_at=started_at,
                error_category="not_configured",
            )
            raise HTTPException(
                status_code=503,
                detail="Ivy AI is not configured on the server.",
            )

        try:
            async with httpx.AsyncClient(
                timeout=httpx.Timeout(
                    connect=_CONNECT_TIMEOUT,
                    read=_READ_TIMEOUT,
                    write=_WRITE_TIMEOUT,
                    pool=_POOL_TIMEOUT,
                )
            ) as client:
                response = await client.post(
                    _IVYAI_URL,
                    headers={
                        "X-API-KEY": api_key,
                        "Accept": "application/json",
                    },
                    files={
                        "input_image": ("scan.jpg", image_bytes, "image/jpeg")
                    },
                )
        except httpx.ConnectTimeout as error:
            self._log_failure(started_at, "connect_timeout")
            raise HTTPException(
                status_code=504,
                detail="Could not connect to Ivy AI in time.",
            ) from error
        except httpx.ReadTimeout as error:
            self._log_failure(started_at, "read_timeout")
            raise HTTPException(
                status_code=504,
                detail="Ivy AI did not return a result in time.",
            ) from error
        except httpx.TimeoutException as error:
            self._log_failure(started_at, "timeout")
            raise HTTPException(
                status_code=504,
                detail="Ivy AI request timed out.",
            ) from error
        except httpx.HTTPError as error:
            self._log_failure(started_at, "transport_error")
            raise HTTPException(
                status_code=502,
                detail="Ivy AI could not be reached.",
            ) from error

        status = response.status_code
        if status == 400:
            self._log_failure(started_at, "invalid_image", status)
            raise HTTPException(
                status_code=400,
                detail="Ivy AI could not process this image. Try a clear JPG photo.",
            )
        if status == 403:
            self._log_failure(started_at, "credentials_rejected", status)
            raise HTTPException(
                status_code=503,
                detail="Ivy AI rejected the server credentials. Check IVYAI_API_KEY.",
            )
        if status == 429:
            self._log_failure(started_at, "rate_limited", status)
            raise HTTPException(
                status_code=429,
                detail="Ivy AI rate limit or quota reached. Try again later.",
            )
        if status == 500:
            self._log_failure(started_at, "provider_error", status)
            raise HTTPException(
                status_code=502,
                detail="Ivy AI is temporarily unavailable.",
            )
        if not response.is_success:
            self._log_failure(started_at, "http_error", status)
            raise HTTPException(
                status_code=502,
                detail="Ivy AI could not complete the screening.",
            )
        if len(response.content) > _MAX_RESPONSE_BYTES:
            self._log_failure(started_at, "oversized_response", status)
            raise HTTPException(
                status_code=502,
                detail="Ivy AI returned an oversized response.",
            )

        try:
            payload: Any = response.json()
        except (json.JSONDecodeError, ValueError):
            self._log_failure(started_at, "invalid_json", status)
            raise HTTPException(
                status_code=502,
                detail="Ivy AI returned invalid JSON.",
            ) from None
        try:
            result = validate_ivy_response(payload)
        except HTTPException:
            self._log_failure(started_at, "invalid_response", status)
            raise

        log_provider_call(
            provider="Ivy AI",
            stage="skin_analysis",
            status_code=status,
            started_at=started_at,
        )
        return result

    @staticmethod
    def _log_failure(
        started_at: float,
        category: str,
        status_code: int | None = None,
    ) -> None:
        log_provider_call(
            provider="Ivy AI",
            stage="skin_analysis",
            status_code=status_code,
            started_at=started_at,
            error_category=category,
        )
        if status_code is not None:
            _logger.warning("Ivy AI returned HTTP %d.", status_code)
