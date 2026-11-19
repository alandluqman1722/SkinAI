from __future__ import annotations

from .schemas import MedicalReportExtraction

_UNAVAILABLE = {
    "en": (
        "Automated medical-report extraction is unavailable. The uploaded file "
        "was preserved only if storage consent was granted and was not interpreted."
    ),
    "ku": (
        "دەرهێنانی خۆکاری زانیاری لە ڕاپۆرتی پزیشکی بەردەست نییە. فایلەکە "
        "تەنها ئەگەر ڕەزامەندی هەڵگرتن درابێت پارێزراوە و شیکاری نەکراوە."
    ),
    "bad": (
        "دەرهێنانا خۆکار یا زانیاری ژ ڕاپۆرتا پزیشکی بەردەست نینە. فایل تەنێ "
        "ئەگەر ڕەزامەندیا هەڵگرتن هەبیت هاتیە پاراستن و نەهاتیە شیکارکرن."
    ),
    "ar": (
        "استخراج المعلومات آليًا من التقرير الطبي غير متاح. لم يُفسر الملف، "
        "ولا يُحفظ إلا عند منح الموافقة على التخزين."
    ),
}


class MedicalReportService:
    async def extract(
        self,
        content: bytes,
        mime_type: str,
        *,
        language: str = "en",
    ) -> MedicalReportExtraction:
        if not content or not mime_type:
            raise ValueError("A validated medical report is required.")
        return MedicalReportExtraction(
            source="unavailable",
            missing_or_unreadable=[_UNAVAILABLE[language]],
            uncertainty=[_UNAVAILABLE[language]],
        )
