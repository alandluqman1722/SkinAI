from __future__ import annotations

import asyncio
import os
import time
from datetime import date
from typing import Any
from urllib.parse import quote

import httpx

from .provider_telemetry import log_provider_call

_OPENFDA_URL = "https://api.fda.gov/drug/label.json"
_DAILYMED_URL = "https://dailymed.nlm.nih.gov/dailymed/services/v2/spls.json"
_REFERENCE_TIMEOUT = 6.0


class MedicalKnowledgeService:
    async def lookup_medication(
        self,
        name: str | None,
        ingredients: list[str],
    ) -> dict[str, Any] | None:
        query = name or (ingredients[0] if ingredients else None)
        if not query:
            return None
        label = await self._openfda_label(query)
        if label is not None:
            return label
        return await self._dailymed_reference(query)

    async def _openfda_label(self, query: str) -> dict[str, Any] | None:
        started_at = time.perf_counter()
        escaped = query.replace("\\", "\\\\").replace('"', '\\"')
        params = {
            "search": (
                f'openfda.brand_name:"{escaped}" OR '
                f'openfda.generic_name:"{escaped}" OR '
                f'openfda.substance_name:"{escaped}"'
            ),
            "limit": "1",
        }
        api_key = os.getenv("OPENFDA_API_KEY", "").strip()
        if api_key:
            params["api_key"] = api_key
        try:
            async with httpx.AsyncClient(
                timeout=httpx.Timeout(_REFERENCE_TIMEOUT, connect=4.0)
            ) as client:
                response = await asyncio.wait_for(
                    client.get(_OPENFDA_URL, params=params),
                    timeout=_REFERENCE_TIMEOUT,
                )
        except (httpx.TimeoutException, asyncio.TimeoutError):
            log_provider_call(
                provider="OpenFDA",
                stage="medication_lookup",
                status_code=None,
                started_at=started_at,
                error_category="timeout",
            )
            return None
        except httpx.HTTPError:
            log_provider_call(
                provider="OpenFDA",
                stage="medication_lookup",
                status_code=None,
                started_at=started_at,
                error_category="transport_error",
            )
            return None
        if response.status_code == 404:
            log_provider_call(
                provider="OpenFDA",
                stage="medication_lookup",
                status_code=response.status_code,
                started_at=started_at,
                error_category="not_found",
            )
            return None
        if not response.is_success:
            log_provider_call(
                provider="OpenFDA",
                stage="medication_lookup",
                status_code=response.status_code,
                started_at=started_at,
                error_category=(
                    "rate_limited"
                    if response.status_code == 429
                    else "http_error"
                ),
            )
            return None
        try:
            results = response.json().get("results", [])
            label = results[0]
            openfda = label.get("openfda", {})
        except (ValueError, IndexError, AttributeError, TypeError):
            log_provider_call(
                provider="OpenFDA",
                stage="medication_lookup",
                status_code=response.status_code,
                started_at=started_at,
                error_category="invalid_response",
            )
            return None
        if not isinstance(openfda, dict):
            log_provider_call(
                provider="OpenFDA",
                stage="medication_lookup",
                status_code=response.status_code,
                started_at=started_at,
                error_category="invalid_response",
            )
            return None
        if not any(
            _name_matches(query, candidate)
            for key in ("brand_name", "generic_name", "substance_name")
            for candidate in (
                openfda.get(key)
                if isinstance(openfda.get(key), list)
                else [openfda[key]]
                if isinstance(openfda.get(key), str)
                else []
            )
            if isinstance(candidate, str)
        ):
            log_provider_call(
                provider="OpenFDA",
                stage="medication_lookup",
                status_code=response.status_code,
                started_at=started_at,
                error_category="no_match",
            )
            return None
        warnings = self._values(label, "warnings", "warnings_and_cautions")
        contraindications = self._values(label, "contraindications")
        interactions = self._values(label, "drug_interactions")
        adverse = self._values(label, "adverse_reactions")
        precautions = self._values(label, "precautions", "general_precautions")
        indications = self._values(label, "indications_and_usage")
        ingredients = self._values(
            openfda,
            "substance_name",
            "active_ingredient",
        )
        result = {
            "active_ingredients": ingredients[:10],
            "category": (label.get("product_type") or [None])[0],
            "intended_uses": indications[:10],
            "how_it_works": "",
            "common_side_effects": adverse[:10],
            "serious_warning_signs": warnings[:10],
            "contraindications": contraindications[:10],
            "interactions": interactions[:10],
            "precautions": precautions[:10],
            "storage_instructions": self._values(label, "storage_and_handling")[:10],
            "source": "U.S. FDA openFDA drug labeling API",
            "source_date": self._label_date(label),
        }
        log_provider_call(
            provider="OpenFDA",
            stage="medication_lookup",
            status_code=response.status_code,
            started_at=started_at,
        )
        return result

    async def _dailymed_reference(self, query: str) -> dict[str, Any] | None:
        started_at = time.perf_counter()
        try:
            async with httpx.AsyncClient(
                timeout=httpx.Timeout(_REFERENCE_TIMEOUT, connect=4.0)
            ) as client:
                response = await asyncio.wait_for(
                    client.get(
                        _DAILYMED_URL,
                        params={"drug_name": query, "page": "1"},
                    ),
                    timeout=_REFERENCE_TIMEOUT,
                )
        except (httpx.TimeoutException, asyncio.TimeoutError):
            log_provider_call(
                provider="DailyMed",
                stage="medication_lookup",
                status_code=None,
                started_at=started_at,
                error_category="timeout",
            )
            return None
        except httpx.HTTPError:
            log_provider_call(
                provider="DailyMed",
                stage="medication_lookup",
                status_code=None,
                started_at=started_at,
                error_category="transport_error",
            )
            return None
        if not response.is_success:
            log_provider_call(
                provider="DailyMed",
                stage="medication_lookup",
                status_code=response.status_code,
                started_at=started_at,
                error_category=(
                    "not_found"
                    if response.status_code == 404
                    else "rate_limited"
                    if response.status_code == 429
                    else "http_error"
                ),
            )
            return None
        try:
            payload = response.json()
            record = payload["data"][0]
            set_id = record["setid"]
        except (ValueError, KeyError, IndexError, TypeError):
            log_provider_call(
                provider="DailyMed",
                stage="medication_lookup",
                status_code=response.status_code,
                started_at=started_at,
                error_category="invalid_response",
            )
            return None
        if not isinstance(set_id, str) or not set_id:
            log_provider_call(
                provider="DailyMed",
                stage="medication_lookup",
                status_code=response.status_code,
                started_at=started_at,
                error_category="invalid_response",
            )
            return None
        drug_names = record.get("drug_name", [])
        if isinstance(drug_names, str):
            drug_names = [drug_names]
        if not isinstance(drug_names, list) or not any(
            isinstance(candidate, str) and _name_matches(query, candidate)
            for candidate in drug_names
        ):
            log_provider_call(
                provider="DailyMed",
                stage="medication_lookup",
                status_code=response.status_code,
                started_at=started_at,
                error_category="no_match",
            )
            return None
        result = {
            "active_ingredients": [],
            "category": None,
            "intended_uses": [],
            "how_it_works": "",
            "common_side_effects": [],
            "serious_warning_signs": [],
            "contraindications": [],
            "interactions": [],
            "precautions": [],
            "storage_instructions": [],
            "source": (
                "NIH DailyMed Structured Product Label "
                f"https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid={quote(set_id)}"
            ),
            "source_date": None,
        }
        log_provider_call(
            provider="DailyMed",
            stage="medication_lookup",
            status_code=response.status_code,
            started_at=started_at,
        )
        return result

    @staticmethod
    def _values(label: dict[str, Any], *fields: str) -> list[str]:
        for field in fields:
            value = label.get(field)
            if isinstance(value, list):
                return [
                    item.strip()[:4000]
                    for item in value
                    if isinstance(item, str) and item.strip()
                ]
        return []

    @staticmethod
    def _label_date(label: dict[str, Any]) -> date | None:
        value = label.get("effective_time")
        if not isinstance(value, str) or len(value) != 8:
            return None
        try:
            return date(int(value[:4]), int(value[4:6]), int(value[6:8]))
        except ValueError:
            return None


def _name_matches(query: str, candidate: str) -> bool:
    normalized_query = "".join(
        character for character in query.casefold() if character.isalnum()
    )
    normalized_candidate = "".join(
        character for character in candidate.casefold() if character.isalnum()
    )
    return bool(
        normalized_query
        and len(normalized_query) >= 4
        and normalized_candidate
        and (
            normalized_query in normalized_candidate
            or normalized_candidate in normalized_query
        )
    )
