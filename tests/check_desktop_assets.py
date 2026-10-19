"""Regression checks for complete desktop animation silhouettes (Pillow only)."""
from pathlib import Path
import json
import unittest

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'desktop' / 'assets'


class DesktopAnimationTests(unittest.TestCase):
    def test_complete_laughter_sequence(self):
        files = sorted(p.name for p in (ASSETS / 'laugh').glob('*.png'))
        self.assertEqual(files, [f'{i:04d}.png' for i in range(541)])
        config = json.loads((ROOT / 'desktop' / 'config.json').read_text(encoding='utf-8'))
        self.assertEqual(config['laugh_frames'], 541)
        self.assertEqual(config['laugh_fps'], 30)

    def test_no_frames_touch_player_edges(self):
        files = list((ASSETS / 'laugh').glob('*.png'))
        files += [ASSETS / 'idle-frame.png', ASSETS / 'stance-frame.png']
        for file in files:
            with self.subTest(frame=file.name), Image.open(file) as image:
                self.assertEqual(image.size, (384, 416))
                self.assertEqual(image.mode, 'RGBA')
                bounds = image.getchannel('A').point(lambda a: 255 if a > 16 else 0).getbbox()
                self.assertIsNotNone(bounds)
                self.assertGreater(bounds[0], 1)
                self.assertGreater(bounds[1], 1)
                self.assertLess(bounds[2], 383)
                self.assertLess(bounds[3], 415)

    def test_pale_belly_survives_laughing_and_falling(self):
        # Actual skin positions that were transparent in the defective assets.
        probes = [(225, 140, 201), (240, 135, 209), (411, 152, 263),
                  (420, 221, 270), (510, 192, 264)]
        for frame, x, y in probes:
            with self.subTest(frame=frame), Image.open(ASSETS / 'laugh' / f'{frame:04d}.png') as image:
                self.assertGreaterEqual(image.getpixel((x, y))[3], 240)


if __name__ == '__main__':
    unittest.main()
