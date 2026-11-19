from __future__ import annotations

import unittest

from backend.skinchat_ai import (
    classify_question,
    policy_response,
    selected_language,
    skincare_unavailable_response,
)


class SkinChatPolicyTests(unittest.TestCase):
    def test_selected_languages_are_preserved(self):
        for language in ("en", "ar", "ku", "bad"):
            with self.subTest(language=language):
                self.assertEqual(selected_language("skin question", language), language)

    def test_urgent_and_diagnosis_questions_keep_deterministic_responses(self):
        self.assertEqual(
            classify_question("I have difficulty breathing", []),
            "urgent",
        )
        self.assertEqual(
            classify_question("Can you diagnose this spot from my photo?", []),
            "diagnosis",
        )
        self.assertIn("urgent", policy_response("urgent", "en").lower())
        self.assertIn("can’t diagnose", policy_response("diagnosis", "en").lower())

    def test_general_skin_questions_are_explicitly_unavailable(self):
        self.assertEqual(
            classify_question("How do I care for oily skin?", []),
            "skincare",
        )
        for language in ("en", "ar", "ku", "bad"):
            with self.subTest(language=language):
                self.assertTrue(skincare_unavailable_response(language).strip())

    def test_unrelated_questions_remain_out_of_scope(self):
        self.assertEqual(
            classify_question("What is the capital of Japan?", []),
            "out_of_scope",
        )
        self.assertTrue(policy_response("out_of_scope", "en").strip())


if __name__ == "__main__":
    unittest.main()
