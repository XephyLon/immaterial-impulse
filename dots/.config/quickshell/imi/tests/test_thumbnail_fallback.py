#!/usr/bin/env python3
"""Regression contracts for safe and resilient wallpaper thumbnails."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class ThumbnailFallbackTests(unittest.TestCase):
    def test_primary_generator_propagates_failures(self):
        source = (ROOT / "scripts/thumbnails/thumbgen.py").read_text(encoding="utf-8")
        self.assertIn("@logger.catch(reraise=True)", source)

    def test_magick_fallback_does_not_fan_out_unbounded_processes(self):
        source = (ROOT / "scripts/thumbnails/generate-thumbnails-magick.sh").read_text(
            encoding="utf-8"
        )
        self.assertNotIn('generate_thumbnail "$f" &', source)
        self.assertNotIn("        wait\n", source)

    def test_missing_cache_entry_falls_back_to_original_image(self):
        thumbnail = (ROOT / "modules/common/widgets/ThumbnailImage.qml").read_text(
            encoding="utf-8"
        )
        delegate = (
            ROOT / "modules/imi/wallpaperSelector/WallpaperDirectoryItem.qml"
        ).read_text(encoding="utf-8")
        self.assertIn("property bool usingSourceFallback: false", thumbnail)
        self.assertIn('Qt.md5(`${Qt.resolvedUrl(sourcePath)}`)', thumbnail)
        self.assertNotIn("encodeURIComponent", thumbnail)
        self.assertIn("root.source = Qt.resolvedUrl(root.sourcePath)", thumbnail)
        self.assertIn("function reloadThumbnail()", thumbnail)
        self.assertIn("thumbnailImage.usingSourceFallback", delegate)
        self.assertIn("thumbnailImage.reloadThumbnail()", delegate)


if __name__ == "__main__":
    unittest.main()
