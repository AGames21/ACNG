import json
import math
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

    def test_event_samples_leave_blends_and_donor_physics_unchanged(self):
        events=[(name,2 if name=='bmw_6cyl_limiter' else 1,128) for name in s.EVENT_SAMPLES]
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);bank=root/'test.bank';bank.write_bytes(fake_bank(self.SAMPLES+events))
            s.write(bank,root,'acng_test')
            before={p.name:p.read_bytes() for p in (root/'sounds').iterdir()}
            files=s.write_events(bank,root,'acng_test')
            for name,data in before.items():self.assertEqual((root/'sounds'/name).read_bytes(),data)
            self.assertEqual(set(files),set(s.EVENT_SAMPLES))
            for path in files.values():
                data=(root/'sounds'/Path(path).name).read_bytes()
                self.assertEqual(data[:4],b'RIFF')
                self.assertEqual(struct.unpack_from('<H',data,22)[0],1)
            parts={'acng_1m_engine':{'mainEngine':{'torque':[[1000,300]]}},
                   'acng_1m_turbo':{'turbocharger':{'wastegateStart':5,'pressurePSI':[[60000,3]]}},
                   'acng_1m_shifter':{'hPattern':{'gearCoordinates':[[1,0,1]]},'acng_shiftSound':{'volume':0.5}}}
            s.apply_events(parts,files,root)
            self.assertEqual(parts['acng_1m_engine'],{'mainEngine':{'torque':[[1000,300]]}})
            turbo=parts['acng_1m_turbo']['turbocharger']
            self.assertEqual(turbo['whineLoopEvent'],files['turbo'])
            self.assertEqual(turbo['bovSoundFileName'],files['flutter_4'])
            self.assertEqual(turbo['pressurePSI'],[[60000,3]])
            # The native lever keeps its own FMOD clicks; the AC recordings go to ACNG's controller.
            self.assertEqual(parts['acng_1m_shifter']['hPattern'],{'gearCoordinates':[[1,0,1]]})
            sound=parts['acng_1m_shifter']['acng_shiftSound']
            self.assertEqual((sound['upSample'],sound['downSample']),(files['gearup'],files['geardn']))
            self.assertGreater(sound['upSeconds'],0)
            self.assertTrue((root/'lua'/'controller'/'acng_shiftSound.lua').is_file())

    def test_missing_events_fail_without_partial_export(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);bank=root/'test.bank';bank.write_bytes(fake_bank(self.SAMPLES))
            with self.assertRaisesRegex(ValueError,'Missing 1M event samples'):
                s.write_events(bank,root,'acng_test')
            self.assertFalse((root/'sounds').exists())

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

    def test_loops_put_idle_under_off_and_on_load_lists(self):
        b = s.loops({n: None for n, _, _ in self.SAMPLES})
        self.assertEqual(b['engine'], [[(650, '1m_idle'), (4000, '1m_off_4000')],
                                       [(650, '1m_idle'), (4000, '1m_on_4000')]])
        self.assertEqual(b['exhaust'][1], [(650, 'ext_1m_idle'), (2500, 'ext1m_on_2500')])
        self.assertEqual(s.IDLE_RPM, 650)  # measured recording rpm, matches the engine idleRPM

    def test_zones_follow_ac_crossfade_windows(self):
        self.assertEqual(s.zone('engine', 1, 650, 2800), (1600, 2000))
        self.assertEqual(s.zone('engine', 0, 650, 2000), (1200, 2400))  # the one wide idle fade
        self.assertEqual(s.zone('engine', 0, 6000, 8000), (5600, 6000))  # ends at the lower loop
        self.assertEqual(s.zone('engine', 1, 4000, 5000), (4300, 4700))  # unknown: centred 400

    def test_each_loop_plays_alone_between_ac_windows(self):
        names = ['1m_idle', 'ext_1m_idle'] + [f'{p}{r}' for p, rs in (
            ('1m_off_', (2000, 4000, 6000, 8000)), ('1m_on_', (2800, 4000, 6000, 8000)),
            ('ext1m_off_', (2500, 4500, 6000, 8000)), ('ext1m_on_', (2500, 4000, 5500, 8000)))
            for r in rs]
        b = s.blends(dict.fromkeys(names))
        self.assertEqual([(tag, rpm, db) for tag, _, rpm, db in b['engine'][1]],
                         [(650, 650, 0), (1600, 650, 0), (2000, 2800, -2.5), (2800, 2800, -2.5),
                          (3200, 4000, -3), (4000, 4000, -3), (4400, 6000, -3), (6000, 6000, -3),
                          (6400, 8000, -3), (8000, 8000, -3)])
        for key in b:
            for entries in b[key]:
                tags = [e[0] for e in entries]
                self.assertEqual(tags, sorted(set(tags)), key)
                # Two different recordings only ever meet across one entry gap (a crossfade window).
                for (_, n1, _, _), (_, n2, _, _), (_, n3, _, _) in zip(entries, entries[1:], entries[2:]):
                    self.assertTrue(n1 == n2 or n2 == n3, (key, n1, n2, n3))

    def test_copies_get_near_whole_tags_and_loop_without_a_seam(self):
        n, rpm = 44100, 4000
        frames, tag = s.copy_length(n, rpm, 3200)
        self.assertLessEqual(abs(tag - 3200) / 3200, s.TAG_SLACK)
        self.assertLess(abs(rpm * n / frames - tag), 0.01)
        self.assertEqual(s.copy_length(n, rpm, rpm), (n, rpm))
        period = 100
        tone = struct.pack(f'<{n}h', *(round(8000 * math.sin(2 * math.pi * i / period)) for i in range(n)))
        for target in (frames, 30000):
            out = struct.unpack(f'<{target}h', s.repitch(tone, target))
            self.assertLessEqual(s.seam_ratio(out), s.SEAM_RATIO, target)
        half = struct.unpack('<2h', s.gain(struct.pack('<2h', 1000, -1000), -6))
        self.assertEqual(half, (501, -501))

    def test_write_and_apply_point_engine_at_build_local_blends(self):
        with tempfile.TemporaryDirectory() as tmp:
            bank, vdir = Path(tmp) / 'car.bank', Path(tmp) / 'v'
            bank.write_bytes(fake_bank([(n, ch, 3000) for n, ch, _ in self.SAMPLES]))
            vdir.mkdir()
            updates = s.write(bank, vdir, 'acng_test')
            blend = json.loads((vdir / 'sounds' / 'acng_1m_engine.sfxBlend2D.json').read_text())
            on = blend['samples'][1]
            self.assertEqual(on[0], ['vehicles/acng_test/sounds/1m_idle.wav', 650])
            self.assertEqual(on[-1], ['vehicles/acng_test/sounds/1m_on_4000_-3dB.wav', 4000])
            for (_, got), want in zip(on, [650, 2800, 3200, 4000], strict=True):
                self.assertLessEqual(abs(got - want) / want, s.TAG_SLACK)
            self.assertTrue(on[1][0].startswith('vehicles/acng_test/sounds/1m_idle_at_'))
            for path, _ in sum(blend['samples'], []):
                self.assertTrue((vdir / 'sounds' / Path(path).name).is_file(), path)
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
        self.assertEqual(engine['soundConfigExhaust']['offLoadGain'], s.OFF_LOAD_GAIN)

    def test_base_eq_cancels_child_part_eq_so_the_final_eq_is_flat(self):
        donors = {'intake_turbo': {'soundConfig': {'$+eqFundamentalGain': 4, '$+eqLowGain': 2, '$+mainGain': 1.5},
                                   'soundConfigExhaust': {'$+eqFundamentalGain': 4}},
                  'exhaust': {'soundConfigExhaust': {'$+lowShelfGain': 12, '$+highShelfGain': -9}},
                  'not_fitted': {'soundConfig': {'$+eqHighGain': 7}}}
        offsets = s.donor_offsets(donors, ['intake_turbo', 'exhaust', '', 'missing'])
        self.assertEqual(offsets['soundConfig'], {'eqFundamentalGain': 4, 'eqLowGain': 2})
        engine = {'mainEngine': {'soundConfig': 'soundConfig', 'soundConfigExhaust': 'soundConfigExhaust'},
                  'soundConfig': {'mainGain': -7}, 'soundConfigExhaust': {'mainGain': -3}}
        updates = {k: {'sampleName': 'x', **s.FLAT_EQ} for k in ('engine', 'exhaust')}
        s.apply(engine, updates, offsets)
        for section in ('soundConfig', 'soundConfigExhaust'):
            for key in s.FLAT_EQ:  # what BeamNG sees after merging the "$+" child keys
                final = engine[section][key] + sum(d.get(section, {}).get('$+' + key, 0)
                                                    for n, d in donors.items() if n != 'not_fitted')
                self.assertEqual(final, 0, (section, key))
        self.assertEqual((engine['soundConfig']['mainGain'], engine['soundConfigExhaust']['mainGain']),
                         (-7 + s.LEVEL_MATCH_DB + s.TRIM_DB['soundConfig'], -3 + s.LEVEL_MATCH_DB))
        # The exterior recording leads; the interior one is a quiet layer, not a second engine.
        self.assertLessEqual(s.TRIM_DB['soundConfig'], s.TRIM_DB['soundConfigExhaust'] - 6)

    def test_clicking_loop_gets_a_crossfaded_seam_and_clean_loops_stay_untouched(self):
        rate, period = 1000, 50
        tone = [round(8000 * math.sin(2 * math.pi * i / period)) for i in range(1000)]
        clean = struct.pack('<1000h', *tone)
        self.assertEqual(s.seamless(clean, rate), clean)
        cut = struct.pack('<1013h', *(tone + tone[:13]))  # stops mid-cycle: a jump at the loop point
        self.assertGreater(s.seam_ratio(struct.unpack('<1013h', cut)), s.SEAM_RATIO)
        out = s.seamless(cut, rate)
        fixed = struct.unpack(f'<{len(out) // 2}h', out)
        self.assertEqual(len(fixed), 1013 - int(rate * s.FADE_S))
        self.assertLessEqual(s.seam_ratio(fixed), s.SEAM_RATIO)


if __name__ == '__main__':
    unittest.main()
