from __future__ import annotations

import os
import re
from typing import Any

from fastapi import HTTPException

_SUPPORTED_LANGUAGES = {"en", "ar", "ku", "bad"}
_SKIN_TERMS = (
    "skin", "skincare", "skin care", "acne", "pimple", "blackhead",
    "whitehead", "oily skin", "dry skin", "sensitive skin", "moistur",
    "cleanser", "sunscreen", "spf", "hydration", "dark spot", "routine",
    "pores", "niacinamide", "hyaluronic", "ceramide", "retinol",
    "dermatologist", "dermatology", "eczema", "psoriasis", "rosacea",
    "dermatitis", "پێست", "چاودێری", "جوانکاری", "جووش", "جوش",
    "دانە", "چەوری", "وشک", "هەستیار", "ڕوتین", "خۆر", "لک",
    "العناية بالبشرة", "البشرة", "الجلد", "حب الشباب", "حبوب",
    "رؤوس سوداء", "رؤوس بيضاء", "دهنية", "جافة", "مختلطة", "حساسة",
    "مرطب", "منظف", "واقي شمس", "ترطيب", "تصبغ", "تصبغات",
)
_URGENT_TERMS = (
    "difficulty breathing", "trouble breathing", "can't breathe",
    "cannot breathe", "severe allergic", "rapidly worsening swelling",
    "serious infection", "high fever", "صعوبة التنفس", "لا أستطيع التنفس",
    "حساسية شديدة", "تورم يزداد", "التهاب شديد", "نەفەس", "هەناسە",
    "ئاوسانی خێرا",
)
_DIAGNOSIS_PATTERNS = tuple(
    re.compile(pattern, re.IGNORECASE)
    for pattern in (
        r"\bdiagnos(?:e|is|ed|ing)\b",
        r"\bdo i have\b",
        r"\bcould (?:this|it) be\b",
        r"\bis (?:this|that|my) (?:spot|mark|mole|lesion|rash|cancer)\b",
        r"\bis it (?:cancer|dangerous|benign|malignant|serious)\b",
        r"\bwhat is this\b",
        r"\b(?:this|my) (?:spot|mark|mole|lesion|rash)\b",
        r"\b(?:cancer|melanoma|malignant)\b",
        r"\b(?:photo|picture|image|uploaded image)\b",
        r"تشخيص|سرطان|ميلانوما|شامة|صورتي|صورة|الصورة",
        r"وێنە|شێرپەنجە|خول|خولەک|تشخیص",
    )
)
_DIRECT_DIAGNOSIS_PATTERNS = tuple(
    re.compile(pattern, re.IGNORECASE)
    for pattern in (
        r"\bdiagnos(?:e|is|ed|ing)\b",
        r"\bdo i have\b",
        r"\b(?:cancer|melanoma|malignant)\b",
        r"تشخيص|سرطان|ميلانوما|تشخیص|شێرپەنجە",
    )
)
_UNRELATED_PATTERNS = tuple(
    re.compile(pattern, re.IGNORECASE)
    for pattern in (
        r"\bwrite\b.*\b(?:python|code|program|essay|joke)\b",
        r"\b(?:football|soccer|capital of|history essay|hack an account)\b",
        r"\b(?:tell|make)\b.*\bjoke\b",
        r"\bhack\b",
        r"\b(?:ignore|bypass|override)\b.*\b(?:instructions|rules|filter)\b",
    )
)
_OUT_OF_SCOPE = {
    "en": (
        "I’m specialized in skincare and skin-health education. "
        "Please ask a question about skincare or a skin-related topic."
    ),
    "ar": (
        "أنا مختص بالتثقيف حول العناية بالبشرة وصحتها. "
        "يرجى طرح سؤال عن العناية بالبشرة أو موضوع متعلق بها."
    ),
    "ku": (
        "من تایبەتم بە زانیاریی گشتی لەبارەی چاودێری و تەندروستی پێست. "
        "تکایە پرسیارێک لەبارەی پێست بکە."
    ),
    "bad": (
        "ئەز دەر بارێ چاڤدێری و تەندروستیا پێستی زانیاریا گشتی ددەم. "
        "هیڤییە پرسیارەکا دەر بارێ پێستی بکە."
    ),
}
_DIAGNOSIS_REFUSAL = {
    "en": (
        "I can’t diagnose a condition or assess a spot from a photograph. "
        "Images are not analyzed by SkinChat. A qualified dermatologist "
        "should examine concerning marks, especially if they change quickly, "
        "bleed, have irregular borders, or do not heal. This is educational "
        "information, not a diagnosis."
    ),
    "ar": (
        "لا أستطيع تشخيص حالة أو تقييم بقعة من صورة، ولا تُحلل الصور في "
        "SkinChat. ينبغي لطبيب جلدية مؤهل فحص العلامات المقلقة، خاصة إذا "
        "تغيرت بسرعة أو نزفت أو كانت حوافها غير منتظمة أو لم تلتئم. "
        "هذه معلومات تثقيفية وليست تشخيصًا."
    ),
    "ku": (
        "ناتوانم نەخۆشییەک تشخیص بکەم یان نیشانەیەک لە وێنە هەڵبسەنگێنم؛ "
        "وێنەکان لە SkinChat شیکار ناکرێن. پزیشکی پێستی پسپۆڕ دەبێت "
        "نیشانە نیگەرانکەرەکان ببینێت، بە تایبەتی ئەگەر زوو بگۆڕێت، "
        "خوێنی لێبێت، سنوری ناڕێکی هەبێت یان چاک نەبێتەوە. ئەمە زانیاریی "
        "گشتییە، نەک تشخیص."
    ),
    "bad": (
        "ئەز نەشێم نەخۆشیەکێ تشخیص بکەم یان نیشانەیەکێ ژ وێنەیێ "
        "هەڵسەنگینم؛ وێنە ل SkinChat شیکار ناکرێت. دکتۆرێ پێست یێ پسپۆر "
        "پێدڤییە نیشانێن نیگەرانکەر ببینیت، ب تایبەتی ئەگەر زوو بگوهۆڕیت، "
        "خوین ژێ بهێت، سنوورێن نەرێک هەبن یان چاک نەبیت. ئەڤە زانیاریا "
        "گشتییە، نە تشخیص."
    ),
}
_URGENT_RESPONSE = {
    "en": (
        "Your symptoms may need urgent medical attention. Please seek urgent "
        "care now; if you are having trouble breathing, contact emergency services."
    ),
    "ar": (
        "قد تحتاج أعراضك إلى رعاية طبية عاجلة. يرجى طلب الرعاية العاجلة الآن، "
        "واتصل بالطوارئ إذا كنت تواجه صعوبة في التنفس."
    ),
    "ku": (
        "لەوانەیە نیشانەکانت پێویستیان بە چاودێری پزیشکیی خێرا هەبێت. "
        "تکایە ئێستا بچۆ بۆ فریاکەوتن؛ ئەگەر هەناسەدانت قورسە پەیوەندی "
        "بە فریاکەوتنەوە بکە."
    ),
    "bad": (
        "دبیت نیشانێن تە پێدڤی چاڤدێریا پزیشکی یا بەلەز هەبن. نوکە بچۆ "
        "چاڤدێریا بەلەز؛ ئەگەر هەناسەدانا تە گرانە، پەیوەندی ب فریاکەوتنێ بکە."
    ),
}
_SKINCHAT_UNAVAILABLE = {
    "en": (
        "SkinChat cannot generate skincare answers right now. You can still "
        "view your saved conversation; consult a qualified dermatologist for "
        "personal medical concerns."
    ),
    "ar": (
        "لا تتوفر إجابات العناية بالبشرة في SkinChat حاليًا. يمكنك عرض "
        "محادثاتك المحفوظة؛ واستشر طبيب جلدية مؤهلًا بشأن حالتك."
    ),
    "ku": (
        "وەڵامی چاودێری پێست لە SkinChat ئێستا بەردەست نییە. دەتوانیت "
        "گفتوگۆ پاشەکەوتکراوەکانت ببینیت؛ بۆ کێشەی تایبەتی تەندروستی "
        "ڕاوێژ بە پزیشکی پێستی پسپۆڕ بکە."
    ),
    "bad": (
        "بەرسڤێن چاڤدێریا پێستی ل SkinChat نوکە بەردەست نینن. تو دکاریت "
        "گفتوگۆیێن پاراستی ببینی؛ بۆ نیگەرانیا تەندروستی یا تایبەت "
        "ڕاوێژا دکتۆرێ پێست یێ پسپۆر وەرگرە."
    ),
}


def detect_language(text: str) -> str:
    normalized = text.lower()
    if any(character in normalized for character in "êîûşç"):
        return "bad"
    if any(
        f" {word} " in f" {normalized} "
        for word in ("tu", "dikare", "çawa", "baş", "ez", "heye", "bikim")
    ):
        return "bad"
    if any(character in text for character in "ەڕڵۆێپچژگڤ"):
        return "ku"
    if any("\u0600" <= character <= "\u06ff" for character in text):
        return "ar"
    return "en"


def selected_language(text: str, language: str | None) -> str:
    return language if language in _SUPPORTED_LANGUAGES else detect_language(text)


def classify_question(
    question: str,
    recent_user_messages: list[str],
    *,
    has_scan_context: bool = False,
) -> str:
    normalized_question = question.strip()
    if any(pattern.search(normalized_question) for pattern in _UNRELATED_PATTERNS):
        return "out_of_scope"

    all_text = " ".join([*recent_user_messages[-6:], normalized_question]).lower()
    if any(term in all_text for term in _URGENT_TERMS):
        return "urgent"

    if has_scan_context:
        if any(
            pattern.search(normalized_question)
            for pattern in _DIRECT_DIAGNOSIS_PATTERNS
        ):
            return "diagnosis"
        return "skincare"

    if any(pattern.search(normalized_question) for pattern in _DIAGNOSIS_PATTERNS):
        return "diagnosis"
    if any(term in all_text for term in _SKIN_TERMS):
        return "skincare"
    return "out_of_scope"


def policy_response(category: str, language: str) -> str:
    if category == "urgent":
        return _URGENT_RESPONSE[language]
    if category == "diagnosis":
        return _DIAGNOSIS_REFUSAL[language]
    return _OUT_OF_SCOPE[language]


def skincare_unavailable_response(language: str) -> str:
    return _SKINCHAT_UNAVAILABLE[language]


def _daily_limit(name: str, default: int) -> int:
    try:
        limit = int(os.getenv(name, str(default)))
    except ValueError as error:
        raise HTTPException(
            status_code=503,
            detail=f"SkinChat configuration {name} must be a positive integer.",
        ) from error
    if limit < 1:
        raise HTTPException(
            status_code=503,
            detail=f"SkinChat configuration {name} must be a positive integer.",
        )
    return limit


def daily_message_limit(claims: dict[str, Any]) -> int:
    is_paid = (
        claims.get("skinchat_plan") == "paid"
        and claims.get("skinchat_subscription_status") == "active"
    )
    if is_paid:
        return _daily_limit("SKINCHAT_PAID_DAILY_LIMIT", 100)
    return _daily_limit("SKINCHAT_FREE_DAILY_LIMIT", 10)
