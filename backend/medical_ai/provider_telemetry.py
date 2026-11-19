from __future__ import annotations

import json
import logging
import time
from typing import Any

_logger = logging.getLogger(__name__)


def log_provider_call(
    *,
    provider: str,
    stage: str,
    status_code: int | None,
    started_at: float,
    error_category: str | None = None,
    prompt_bytes: int | None = None,
    context_bytes: int | None = None,
    system_instruction_bytes: int | None = None,
    prompt_tokens: int | None = None,
    output_tokens: int | None = None,
) -> None:
    event: dict[str, Any] = {
        "event": "medical_provider_call",
        "provider": provider,
        "stage": stage,
        "http_status": status_code,
        "elapsed_ms": round((time.perf_counter() - started_at) * 1000),
        "error_category": error_category,
    }
    if prompt_bytes is not None:
        event["prompt_bytes"] = prompt_bytes
    if context_bytes is not None:
        event["context_bytes"] = context_bytes
    if system_instruction_bytes is not None:
        event["system_instruction_bytes"] = system_instruction_bytes
    if prompt_tokens is not None:
        event["prompt_tokens"] = prompt_tokens
    if output_tokens is not None:
        event["output_tokens"] = output_tokens
    _logger.log(
        logging.WARNING if error_category else logging.INFO,
        json.dumps(event, separators=(",", ":"), sort_keys=True),
    )
