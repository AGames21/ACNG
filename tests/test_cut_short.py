import argparse
import json
import sys
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import cut_short  # noqa: E402

PLAN = ROOT / 'tools' / 'shorts' / 'tires-v1.json'


class CutShortTests(unittest.TestCase):
    def test_committed_plan_is_valid_and_short(self):
        plan = json.loads(PLAN.read_text(encoding='utf-8'))
        clips = {'heat': Path('h'), 'cool': Path('c'), 'dirt': Path('d')}
        segs = cut_short.validate(plan, clips)
        self.assertEqual((segs[0]['kind'], segs[-1]['kind']), ('card', 'card'))
        self.assertLessEqual(sum(cut_short.seg_seconds(s) for s in segs), 60)  # fits a Short

    def test_1440p_crop_and_speed_audio(self):
        cut_short.configure_size(2560,1440)
        self.assertEqual(cut_short.HUD_BOX,(2200,1040,349,320))
        cut_short.configure_size(1920,1080)
        self.assertEqual(cut_short.audio_tempo(2.5),'atempo=2,atempo=1.25')
        self.assertEqual(cut_short.audio_tempo(0.25),'atempo=0.5,atempo=0.5')
        seg={'kind':'clip','clip':'a','start':0,'end':10,'speed':2.5,'inset':False}
        cmd=cut_short.clip_args('ffmpeg',seg,Path('a'),Path('b'),60,Path('c'),True)
        self.assertIn('[a]',cmd)
        self.assertNotIn('-an',cmd)
        self.assertIn('title=BeamNG game audio',cmd)

    def test_validate_rejects_bad_segments(self):
        clips = {'a': Path('a')}
        for seg in ({'kind': 'card'}, {'kind': 'clip', 'clip': 'b', 'start': 0, 'end': 1, 'head': 'H', 'sub': 'S'},
                    {'kind': 'clip', 'clip': 'a', 'start': 2, 'end': 1, 'head': 'H', 'sub': 'S'},
                    {'kind': 'clip', 'clip': 'a', 'start': 0, 'end': 1, 'head': 'H'}, {'kind': 'pan'}):
            with self.assertRaises(ValueError):
                cut_short.validate({'segments': [seg]}, clips)
        with self.assertRaises(ValueError):
            cut_short.validate({'segments': []}, clips)
        with self.assertRaises(argparse.ArgumentTypeError):
            cut_short.parse_clip('heat')

    def test_overlay_says_unofficial_and_escapes(self):
        seg = {'kind': 'clip', 'head': 'A & B', 'sub': 'x < y', 'speed': 2.5, 'inset': True}
        text = cut_short.overlay_svg(seg)
        ET.fromstring(text)
        self.assertIn('UNOFFICIAL MOD', text)
        self.assertIn('2.5x SPEED', text)
        self.assertIn('LIVE TIRE HUD', text)
        self.assertNotIn('LIVE TIRE HUD', cut_short.overlay_svg(dict(seg, inset=False)))

    def test_clip_args_crop_the_hud_and_trim(self):
        seg = {'kind': 'clip', 'clip': 'a', 'start': 1, 'end': 11, 'speed': 2, 'inset': True}
        args = cut_short.clip_args('ffmpeg', seg, Path('in.mp4'), Path('ov.png'), 60, Path('out.mp4'))
        graph = args[args.index('-filter_complex') + 1]
        x, y, w, h = cut_short.HUD_BOX
        self.assertIn(f'crop={w}:{h}:{x}:{y}', graph)
        self.assertIn('setpts=(PTS-STARTPTS)/2', graph)
        self.assertEqual(args[args.index('-t') + 1], '5.000')
        self.assertEqual((args[args.index('-ss') + 1], args[args.index('-to') + 1]), ('1.000', '11.000'))
        self.assertEqual(args[-1], 'out.mp4')
        plain = cut_short.clip_args('ffmpeg', dict(seg, inset=False), Path('i'), Path('o'), 60, Path('x'))
        self.assertNotIn('crop=', plain[plain.index('-filter_complex') + 1])


if __name__ == '__main__':
    unittest.main()
