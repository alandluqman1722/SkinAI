from __future__ import annotations

from fastapi import HTTPException

from .. import ai_service
from ..ivy_ai_provider import IvyAIProvider


class SkinAnalysisService:
    def __init__(self, provider: IvyAIProvider | None = None) -> None:
        self._provider = provider or IvyAIProvider()

    async def analyze(
        self,
        jpeg_bytes: bytes,
        *,
        body_location: str,
        symptoms_duration: str,
        symptoms_details: str,
    ) -> dict[str, object]:
        if ai_service._mock_enabled():
            raise HTTPException(
                status_code=503,
                detail="Medical assessment requires the live Ivy AI screening provider.",
            )
        return await self._provider.analyze(jpeg_bytes)
