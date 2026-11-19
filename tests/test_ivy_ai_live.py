from __future__ import annotations

import asyncio
import os
import unittest
from io import BytesIO

from PIL import Image

from backend.ivy_ai_provider import IvyAIProvider


@unittest.skipUnless(
    os.getenv("RUN_REAL_IVYAI_TESTS") == "1"
    and bool(os.getenv("IVYAI_API_KEY", "").strip()),
    "Set RUN_REAL_IVYAI_TESTS=1 and configure a newly rotated IVYAI_API_KEY.",
)
class IvyAILiveIntegrationTests(unittest.TestCase):
    def test_synthetic_image_returns_documented_screening_fields(self):
        image = Image.new("RGB", (64, 64), color=(170, 125, 100))
        buffer = BytesIO()
        image.save(buffer, format="JPEG")

        result = asyncio.run(IvyAIProvider().analyze(buffer.getvalue()))

        self.assertIsInstance(result["result"], str)
        self.assertGreater(len(result["result"]), 0)
        self.assertIsInstance(result["confidence"], float)
        self.assertGreaterEqual(result["confidence"], 0)
        self.assertLessEqual(result["confidence"], 100)
        self.assertIsInstance(result["summary"], str)
        self.assertGreater(len(result["summary"]), 0)


if __name__ == "__main__":
    unittest.main()
