import re
import sys
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import brand_kit  # noqa: E402


class BrandKitTests(unittest.TestCase):
    def test_svgs_parse_and_use_only_the_palette(self):
        allowed = set(c.lower() for c in brand_kit.PALETTE) | {'#3a4048'}
        for path, text in brand_kit.build().items():
            ET.fromstring(text)
            self.assertTrue(text.isascii(), path)
            self.assertLessEqual(set(c.lower() for c in re.findall(r'#[0-9A-Fa-f]{6}', text)), allowed, path)

    def test_committed_files_match_the_generator(self):
        for path, text in brand_kit.build().items():
            self.assertTrue(path.exists(), f'{path} missing: run python tools/brand_kit.py')
            committed = path.read_text(encoding='ascii').replace('\r\n', '\n')  # autocrlf checkouts
            self.assertEqual(committed, text, f'{path} is stale: run python tools/brand_kit.py')

    def test_public_artwork_says_unofficial(self):
        files = brand_kit.build()
        self.assertIn('Unofficial mod', files[brand_kit.BRAND / 'acng-title-card.svg'])
        self.assertIn('Unofficial mod', files[brand_kit.BANNER])
        self.assertNotIn('BeamNG GmbH logo', ''.join(files.values()))


if __name__ == '__main__':
    unittest.main()
