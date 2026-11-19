from __future__ import annotations

import math

from .schemas import (
    AssessmentGuidance,
    MedicalReportExtraction,
    MedicationRecognition,
    PatientInput,
)

_COPY = {
    "en": {
        "summary": (
            "Ivy AI screening returned “{result}” with a provider score of "
            "{confidence}/100. This is a screening prediction, not a diagnosis."
        ),
        "skin": (
            "Screening prediction: {result}. Provider score: {confidence}/100. "
            "Provider summary: {summary}"
        ),
        "no_medication": "No current medication was reported.",
        "medication_unknown": (
            "A medication was reported, but no name was entered. Package "
            "images are not automatically read; medication details are unavailable."
        ),
        "medication": (
            "You reported using “{name}”. Package recognition is unavailable; "
            "unentered package details are unknown."
        ),
        "verified_medication": (
            "You reported using “{name}”. The cited label information is "
            "reference material only; suitability for your condition has not "
            "been assessed."
        ),
        "no_examination": "No previous examination details were supplied.",
        "examination": (
            "The following examination details were entered by you and have "
            "not been independently verified: {details}"
        ),
        "recommendation": (
            "Discuss this screening result and any persistent or changing "
            "symptoms with a qualified dermatologist."
        ),
        "medication_warning": (
            "Do not start, change, or stop medication without advice from a "
            "qualified healthcare professional."
        ),
        "follow_up": (
            "A qualified clinician can review the screening result and your "
            "reported history."
        ),
        "urgent": (
            "Seek urgent care for breathing difficulty, a severe allergic "
            "reaction, rapidly worsening swelling, uncontrolled bleeding, "
            "or signs of a serious infection."
        ),
        "disclaimer": (
            "This is an automated screening result and educational summary, "
            "not a confirmed diagnosis or medical advice. It does not replace "
            "assessment by a qualified healthcare professional."
        ),
        "missing": (
            "The screening result is not a diagnosis. Missing medication "
            "package details and unprovided examination details were not "
            "inferred."
        ),
    },
    "ku": {
        "summary": (
            "پشکنینی Ivy AI ئەنجامی «{result}» و پلەی دڵنیایی دابینکەری "
            "{confidence}/100ی گەڕاندەوە. ئەمە پێشبینیی پشکنینە، نەک تشخیص."
        ),
        "skin": (
            "پێشبینیی پشکنین: {result}. پلەی دابینکەر: {confidence}/100. "
            "پوختەی دابینکەر: {summary}"
        ),
        "no_medication": "هیچ دەرمانێکی ئێستا ڕاپۆرت نەکراوە.",
        "medication_unknown": (
            "دەرمانێک ڕاپۆرت کراوە، بەڵام ناوێک نەنووسراوە. وێنەی پێچان "
            "بە شێوەی خۆکار ناخوێندرێتەوە و وردەکاریی دەرمان بەردەست نییە."
        ),
        "medication": (
            "تۆ ڕاپۆرتت کردووە کە «{name}» بەکاردەهێنیت. ناسینەوەی پێچان "
            "بەردەست نییە و زانیاریی نەنووسراو نەزانراوە."
        ),
        "verified_medication": (
            "تۆ ڕاپۆرتت کردووە کە «{name}» بەکاردەهێنیت. زانیاریی لیبێڵی "
            "سەرچاوەدراو تەنها زانیاریی سەرچاوەیە و گونجاوی دەرمانەکە "
            "هەڵنەسەنگێنراوە."
        ),
        "no_examination": "هیچ وردەکارییەکی پشکنینی پێشووتر نەدراوە.",
        "examination": (
            "ئەم وردەکارییەکانی پشکنین لەلایەن تۆوە نووسراون و بە سەربەخۆیی "
            "پشتڕاست نەکراونەتەوە: {details}"
        ),
        "recommendation": (
            "ئەنجامی پشکنین و نیشانە بەردەوام یان گۆڕاوەکان لەگەڵ پزیشکی "
            "پێستی پسپۆڕ باس بکە."
        ),
        "medication_warning": (
            "بێ ڕاوێژی کادری تەندروستی پسپۆڕ دەرمان دەست پێ مەکە، مەگۆڕە یان مەوەستێنە."
        ),
        "follow_up": (
            "کادرێکی پزیشکی پسپۆڕ دەتوانێت ئەنجامی پشکنین و مێژووی ڕاپۆرتکراوت پێداچوونەوە بکات."
        ),
        "urgent": (
            "بۆ قورسی هەناسەدان، کاردانەوەی هەستیاریی توند، ئاوسانی خێرا، "
            "خوێنڕشتنی کۆنترۆڵنەکراو یان نیشانەی تووشبوونی توند، خێرا یارمەتی پزیشکی وەربگرە."
        ),
        "disclaimer": (
            "ئەمە ئەنجامی پشکنینی خۆکار و پوختەی فێرکارییە، نەک تشخیصی پشتڕاستکراوە "
            "یان ڕاوێژی پزیشکی. جێگرەوەی هەڵسەنگاندنی کادری تەندروستی پسپۆڕ نییە."
        ),
        "missing": (
            "ئەنجامی پشکنین تشخیص نییە. وردەکاریی ونبووی دەرمان و پشکنینی "
            "نەدراو بە خەمڵاندن پڕ نەکراونەتەوە."
        ),
    },
    "bad": {
        "summary": (
            "پشکنینا Ivy AI ئەنجاما «{result}» و پلەیا دڵنیاییا دابینکەری "
            "{confidence}/100 گەڕاندەوە. ئەڤە پێشبینیا پشکنینێیە، نە تشخیص."
        ),
        "skin": (
            "پێشبینیا پشکنینێ: {result}. پلەیا دابینکەری: {confidence}/100. "
            "پوختەیا دابینکەری: {summary}"
        ),
        "no_medication": "چ دەرمانێن نوکە نەهاتیە ڕاپۆرتکرن.",
        "medication_unknown": (
            "دەرمانەک هاتیە ڕاپۆرتکرن، بەڵام ناڤەک نەهاتیە نڤیسین. وێنەیا "
            "پێچانێ خۆکارانە ناخوێنرێتەوە و وردەکاریێن دەرمانێ بەردەست نینن."
        ),
        "medication": (
            "تە ڕاپۆرت کریە کو «{name}» بکاردهینی. ناسینا پێچانێ بەردەست "
            "نینە و زانیاریێن نەهاتیە نڤیسین نەنزانرین."
        ),
        "verified_medication": (
            "تە ڕاپۆرت کریە کو «{name}» بکاردهینی. زانیاریا لیبێلا سەرچاوەدری "
            "تەنێ زانیاریا سەرچاوەیە و گونجایا دەرمانێ نەهاتیە هەلسەنگاندن."
        ),
        "no_examination": "چ وردەکاریێن پشکنینێن بەرێ نەهاتیە دان.",
        "examination": (
            "ئەڤ وردەکاریێن پشکنینێ ژ لایێ تەڤە هاتینە نڤیسین و ب سەربەخۆیی "
            "نەهاتینە پشتڕاستکرن: {details}"
        ),
        "recommendation": (
            "ئەڤ ئەنجاما پشکنینێ و نیشانێن بەردەوام یان گوهۆڕی دگەل دکتۆرێ "
            "پێستی یێ پسپۆر باس بکە."
        ),
        "medication_warning": (
            "بێ ڕاوێژا کارمەندەکێ تەندروستی یێ پسپۆر دەرمان دەست پێ مەکە، مەگوهۆڕە یان مەوەستینە."
        ),
        "follow_up": (
            "کارمەندەکێ پزیشکی یێ پسپۆر دەتوانیت ئەنجاما پشکنینێ و مێژویا تە ڕاپۆرتکری پێداچوونەوە بکەت."
        ),
        "urgent": (
            "بۆ گرانیا هەناسەدانێ، کاردانەوەیا هەستیاریا توند، ئاوسانا خێرا، "
            "خوینڕشتنا بێ کۆنترۆل یان نیشانێن تووشبوونا توند، نوکە چاڤدێریا پزیشکی وەرگرە."
        ),
        "disclaimer": (
            "ئەڤە ئەنجاما پشکنینا خۆکار و پوختەیا فێرکارییە، نە تشخیصا پشتڕاستکری "
            "یان ڕاوێژا پزیشکی. جهگرتی هەلسەنگاندنا کارمەندەکێ تەندروستی یێ پسپۆر نینە."
        ),
        "missing": (
            "ئەنجاما پشکنینێ تشخیص نینە. وردەکاریێن دەرمانا ونبووی و پشکنینێن "
            "نەهاتیە دان ب خەمڵاندنێ نەهاتینە پڕکرن."
        ),
    },
    "ar": {
        "summary": (
            "أعاد فحص Ivy AI نتيجة «{result}» بدرجة مزود {confidence}/100. "
            "هذا تنبؤ للفحص وليس تشخيصًا."
        ),
        "skin": (
            "تنبؤ الفحص: {result}. درجة المزود: {confidence}/100. "
            "ملخص المزود: {summary}"
        ),
        "no_medication": "لم يُذكر استخدام دواء حالي.",
        "medication_unknown": (
            "تم الإبلاغ عن دواء، لكن لم يُدخل اسمه. لا تُقرأ صور العبوات آليًا "
            "وتفاصيل الدواء غير متاحة."
        ),
        "medication": (
            "أفدت باستخدام «{name}». التعرف على العبوة غير متاح؛ وتفاصيل "
            "العبوة التي لم تدخلها غير معروفة."
        ),
        "verified_medication": (
            "أفدت باستخدام «{name}». معلومات النشرة المشار إليها مرجعية فقط، "
            "ولم تُقيّم ملاءمة الدواء لحالتك."
        ),
        "no_examination": "لم تُقدّم تفاصيل عن فحوصات سابقة.",
        "examination": (
            "أدخلتَ تفاصيل الفحص التالية ولم يتم التحقق منها بشكل مستقل: {details}"
        ),
        "recommendation": (
            "ناقش نتيجة الفحص والأعراض المستمرة أو المتغيرة مع طبيب جلدية مؤهل."
        ),
        "medication_warning": (
            "لا تبدأ دواءً أو تغيّره أو توقفه دون استشارة مختص رعاية صحية مؤهل."
        ),
        "follow_up": (
            "يمكن لمختص مؤهل مراجعة نتيجة الفحص والتاريخ الذي أبلغت عنه."
        ),
        "urgent": (
            "اطلب رعاية عاجلة عند صعوبة التنفس أو تفاعل تحسسي شديد أو تورم "
            "يتفاقم سريعًا أو نزيف لا يمكن السيطرة عليه أو علامات عدوى خطيرة."
        ),
        "disclaimer": (
            "هذه نتيجة فحص آلي وملخص تثقيفي، وليست تشخيصًا مؤكدًا أو نصيحة طبية. "
            "ولا تغني عن تقييم مختص رعاية صحية مؤهل."
        ),
        "missing": (
            "نتيجة الفحص ليست تشخيصًا. لم يتم تخمين تفاصيل الدواء المفقودة أو "
            "تفاصيل الفحوصات التي لم تُقدّم."
        ),
    },
}


class AssessmentReportService:
    async def generate(
        self,
        *,
        patient: PatientInput,
        skin_analysis: dict[str, object],
        medication: MedicationRecognition | None,
        examinations: list[MedicalReportExtraction],
    ) -> AssessmentGuidance:
        copy = _COPY[patient.language]
        result = skin_analysis.get("result")
        raw_confidence = skin_analysis.get("confidence")
        summary = skin_analysis.get("summary")
        if (
            not isinstance(result, str)
            or not result.strip()
            or isinstance(raw_confidence, bool)
            or not isinstance(raw_confidence, (int, float))
            or not math.isfinite(raw_confidence)
            or not 0 <= raw_confidence <= 100
            or not isinstance(summary, str)
            or not summary.strip()
        ):
            raise ValueError("A validated Ivy AI screening result is required.")
        confidence = float(raw_confidence)
        patient_summary = copy["summary"].format(
            result=result,
            confidence=f"{confidence:g}",
        )
        skin_context = copy["skin"].format(
            result=result,
            confidence=f"{confidence:g}",
            summary=summary,
        )

        if medication is None:
            medication_explanation = copy["no_medication"]
        elif medication.medicine_name and medication.verified:
            medication_explanation = copy["verified_medication"].format(
                name=medication.medicine_name,
            )
        elif medication.medicine_name:
            medication_explanation = copy["medication"].format(
                name=medication.medicine_name,
            )
        else:
            medication_explanation = copy["medication_unknown"]

        reported_examinations = [
            examination
            for examination in examinations
            if examination.source == "patient_reported"
        ]
        if reported_examinations:
            details: list[str] = []
            for examination in reported_examinations:
                details.extend(
                    value
                    for value in (
                        examination.examination_date,
                        *examination.doctor_findings,
                        *examination.documented_diagnosis,
                    )
                    if value and value.strip()
                )
            examination_explanation = copy["examination"].format(
                details="; ".join(details),
            )
        else:
            examination_explanation = copy["no_examination"]

        missing_information = [copy["missing"]]
        for examination in examinations:
            missing_information.extend(examination.missing_or_unreadable)

        return AssessmentGuidance(
            patient_summary=patient_summary,
            skin_analysis_context=skin_context,
            medication_explanation=medication_explanation,
            examination_explanation=examination_explanation,
            reassuring_observations=[],
            concerning_observations=[],
            missing_information=missing_information[:20],
            recommendations=[
                copy["recommendation"],
                copy["medication_warning"],
            ],
            clinician_follow_up=copy["follow_up"],
            urgent_care_guidance=copy["urgent"],
            disclaimer=copy["disclaimer"],
        )
