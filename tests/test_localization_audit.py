import unittest
from pathlib import Path

from tools.localization_audit import audit


PROJECT_ROOT = Path(__file__).resolve().parents[1]


class LocalizationAuditTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.report = audit(PROJECT_ROOT)

    def test_sorani_arabic_and_english_catalogs_have_matching_keys(self):
        for language in ("en", "ku", "ar"):
            for domain, missing in self.report["missing"][language].items():
                self.assertEqual(missing, [], f"{language}.{domain}")
                self.assertEqual(
                    self.report["extra"][language][domain],
                    [],
                    f"{language}.{domain}",
                )

    def test_badini_catalog_is_complete(self):
        for domain in ("app", "settings", "notifications", "routines", "widgets"):
            self.assertEqual(self.report["missing"]["bad"][domain], [], domain)
            self.assertEqual(self.report["extra"]["bad"][domain], [], domain)

    def test_catalog_has_no_duplicate_or_empty_entries_or_invalid_references(self):
        self.assertEqual(self.report["duplicates"], [])
        self.assertEqual(self.report["empty_values"], [])
        self.assertEqual(self.report["invalid_references"], [])

    def test_audit_finds_remaining_hardcoded_visible_candidates(self):
        candidates = self.report["hardcoded_visible_candidates"]
        self.assertTrue(
            any("body_region_selector.dart" in item for item in candidates)
        )
        self.assertFalse(any("scan_report.dart" in item for item in candidates))


if __name__ == "__main__":
    unittest.main()
