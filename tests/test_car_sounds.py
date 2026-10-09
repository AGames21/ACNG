import json
import struct
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'converters'))
import car_sounds as s


def fake_bank(samples):
    """Synthetic RIFF-wrapped FSB5 (version 1, PCM16) holding (name, channels, frames) samples."""
    headers, data, names = b'', b'', b''
    offsets = []
    for k, (name, channels, frames) in enumerate(samples):
        pcm = struct.pack(f'<{frames * channels}h', *range(frames * channels))
        v = (8 << 1) | ((channels - 1) << 5) | ((len(data) // 32) << 7) | (frames << 34)
        if k == 0:  # one optional chunk to prove chunks are skipped
            v |= 1
            headers += struct.pack('<Q', v) + struct.pack('<I', (13 << 25) | (4 << 1)) + b'\0' * 4
        else:
            headers += struct.pack('<Q', v)
        data += pcm + b'\0' * (-len(pcm) % 32)
        offsets.append(4 * len(samples) + len(names))
        names += name.encode() + b'\0'
    table = struct.pack(f'<{len(samples)}I', *offsets) + names
    head = b'FSB5' + struct.pack('<6I', 1, len(samples), len(headers), len(table), len(data), 2)
    return b'RIFFxxxxFEV ' + head + b'\0' * (60 - len(head)) + headers + table + data


class SoundContracts(unittest.TestCase):
    SAMPLES = [('1m_idle', 2, 4), ('1m_on_4000', 2, 3), ('1m_off_4000', 2, 3),
               ('ext_1m_idle', 1, 5), ('ext1m_on_2500', 1, 2), ('ext1m_off_2500', 1, 2), ('horn', 1, 1)]

    def test_reads_names_rates_channels_and_pcm(self):
        got = s.read_fsb(fake_bank(self.SAMPLES))
        self.assertEqual(set(got), {n for n, _, _ in self.SAMPLES})
        rate, ch, pcm = got['1m_on_4000']
        self.assertEqual((rate, ch, struct.unpack('<6h', pcm)), (44100, 2, (0, 1, 2, 3, 4, 5)))
        self.assertEqual(len(got['ext_1m_idle'][2]), 10)

    def test_stereo_downmixes_to_mono_wav(self):
        pcm = s.mono(struct.pack('<4h', 100, 300, -10, -30), 2)
        self.assertEqual(struct.unpack('<2h', pcm), (200, -20))
        w = s.wav(pcm, 44100)
        self.assertEqual((w[:4], w[8:12], len(w)), (b'RIFF', b'WAVE', 44 + 4))

    def test_blends_put_idle_under_off_and_on_load_lists(self):
        b = s.blends({n: None for n, _, _ in self.SAMPLES})
        self.assertEqual(b['engine'], [[(800, '1m_idle'), (4000, '1m_off_4000')],
                                       [(800, '1m_idle'), (4000, '1m_on_4000')]])
        self.assertEqual(b['exhaust'][1], [(800, 'ext_1m_idle'), (2500, 'ext1m_on_2500')])

    def test_write_and_apply_point_engine_at_build_local_blends(self):
        with tempfile.TemporaryDirectory() as tmp:
            bank, vdir = Path(tmp) / 'car.bank', Path(tmp) / 'v'
            bank.write_bytes(fake_bank(self.SAMPLES))
            vdir.mkdir()
            updates = s.write(bank, vdir, 'acng_test')
            blend = json.loads((vdir / 'sounds' / 'acng_1m_engine.sfxBlend2D.json').read_text())
            self.assertEqual(blend['samples'][1][1], ['vehicles/acng_test/sounds/1m_on_4000.wav', 4000])
            self.assertTrue((vdir / 'sounds' / 'ext1m_off_2500.wav').is_file())
            self.assertFalse((vdir / 'sounds' / 'horn.wav').exists())
        engine = {'mainEngine': {'soundConfig': 'soundConfig', 'soundConfigExhaust': 'soundConfigExhaust'},
                  'soundConfig': {'sampleName': 'I6_2_engine', 'mainGain': -7, 'eqHighGain': -10},
                  'soundConfigExhaust': {'sampleName': 'I6_2_exhaust'}}
        s.apply(engine, updates)
        self.assertEqual(engine['soundConfig']['sampleName'], 'acng_1m_engine')
        self.assertEqual(engine['soundConfig']['sampleFolder'], 'vehicles/acng_test/sounds/')
        self.assertEqual((engine['soundConfig']['mainGain'], engine['soundConfig']['eqHighGain']), (-7, 0))
        self.assertEqual(engine['soundConfigExhaust']['sampleName'], 'acng_1m_exhaust')


if __name__ == '__main__':
    unittest.main()
