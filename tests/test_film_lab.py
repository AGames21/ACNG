import argparse
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import film_lab  # noqa: E402


class FilmLabTests(unittest.TestCase):
    def test_parsers(self):
        self.assertEqual(film_lab.parse_size('1920x1080'), (1920, 1080))
        self.assertEqual(film_lab.parse_clip('dirt=drive_start:drive_end'), ('dirt', 'drive_start', 'drive_end'))
        for bad in ('1920', 'x1080', '1920x1080x2'):
            with self.assertRaises(argparse.ArgumentTypeError):
                film_lab.parse_size(bad)
        with self.assertRaises(argparse.ArgumentTypeError):
            film_lab.parse_clip('dirt=drive_start')

    def test_profile_is_written_only_when_new(self):
        with tempfile.TemporaryDirectory() as tmp:
            lab = Path(tmp) / 'ACNG-film-x' / 'current'
            film_lab.prepare_profile(lab, 1920, 1080)
            settings = json.loads((lab / 'settings' / 'settings.json').read_text(encoding='utf-8'))
            self.assertEqual(settings, {'GraphicDisplayModes': 'Window', 'GraphicDisplayResolutions': '1920 1080'})
            layout = json.loads((lab / 'settings/ui_apps/layouts/default/freeroam.uilayout.json').read_text(encoding='utf-8'))
            self.assertEqual([a['appName'] for a in layout['apps']], ['acngControl', 'acngTires'])
            self.assertEqual(layout['type'], 'freeroam')
            self.assertTrue(all(layout['removedApps'][name] is True for name in film_lab.STOCK_APPS))
            with self.assertRaises(RuntimeError):
                film_lab.prepare_profile(lab, 1920, 1080)

    def test_1440p_has_no_window_title_bar(self):
        self.assertEqual(film_lab.lab_settings(2560,1440)['GraphicDisplayModes'],'Fullscreen')

    def test_layout_follows_the_game_original(self):
        with tempfile.TemporaryDirectory() as tmp:
            orig = Path(tmp) / 'settings/ui_apps/originalLayouts/default/freeroam.uilayout.json'
            orig.parent.mkdir(parents=True)
            orig.write_text('{"version": 0.6, "removedApps": {"oldApp": 2},\n'
                            ' "apps": [{"appName": "tacho2", "appVersion": 3}, {"appName": "newApp"},],}', encoding='utf-8')
            original = film_lab.original_layout(tmp)
            layout = film_lab.film_layout(original)
            self.assertEqual(layout['version'], 0.6)
            self.assertEqual(layout['removedApps'], {'oldApp': 2, 'tacho2': True, 'newApp': True})
            self.assertEqual([a['appName'] for a in layout['apps']], ['acngControl', 'acngTires'])
            self.assertIsNone(film_lab.original_layout(Path(tmp) / 'missing'))

    def test_stop_refuses_player_process(self):
        from unittest.mock import patch
        with patch.object(film_lab.subprocess,'check_output',return_value='BeamNG.drive.x64.exe -userpath player'):
            with patch.object(film_lab.subprocess,'run') as run:
                with self.assertRaises(RuntimeError):film_lab.stop_lab(1,Path('ACNG-film/current'))
                run.assert_not_called()

    def test_new_cues_in_order_once(self):
        data = {'cues': [{'name': 'drive_end', 'seq': 2}, {'name': 'drive_start', 'seq': 1}]}
        self.assertEqual([c['name'] for c in film_lab.new_cues(data, set())], ['drive_start', 'drive_end'])
        self.assertEqual([c['name'] for c in film_lab.new_cues(data, {1})], ['drive_end'])
        self.assertEqual(film_lab.new_cues(None, set()), [])

    def test_clip_windows_pad_clamp_and_skip(self):
        times = {'drive_start': 1.0, 'drive_end': 40.0}
        clips = [('drive', 'drive_start', 'drive_end'), ('missing', 'drive_start', 'nope'),
                 ('backwards', 'drive_end', 'drive_start')]
        self.assertEqual(film_lab.clip_windows(times, clips, 1.5, 1.5, length=41.0), [('drive', 0.0, 41.0)])
        self.assertEqual(film_lab.clip_windows(times, clips[:1], 0.5, 2.0), [('drive', 0.5, 42.0)])

    def test_ffmpeg_args(self):
        rec = film_lab.record_args('ffmpeg', (10, 20, 1920, 1080), 60, Path('raw.mp4'), ['-c:v', 'libx264'])
        self.assertEqual(rec[rec.index('-f') + 1], 'gdigrab')
        self.assertEqual(rec[rec.index('-video_size') + 1], '1920x1080')
        self.assertEqual((rec[rec.index('-offset_x') + 1], rec[rec.index('-offset_y') + 1]), ('10', '20'))
        self.assertEqual(rec[-1], 'raw.mp4')
        from unittest.mock import patch
        with patch.object(film_lab, 'encoder_args', return_value=['-c:v','libx264']):
            cut = film_lab.cut_args('ffmpeg', Path('raw.mp4'), 1.25, 9.5, Path('clip.mp4'))
        self.assertIn('0:a:0?', cut)
        self.assertIn('title=BeamNG game audio', cut)
        self.assertEqual((cut[cut.index('-ss') + 1], cut[cut.index('-to') + 1]), ('1.250', '9.500'))
        self.assertEqual(cut[-1], 'clip.mp4')


if __name__ == '__main__':
    unittest.main()
