"""Offline overlay safety before altering the local game's configuration."""
import configparser
import importlib.util
from pathlib import Path
import unittest

spec=importlib.util.spec_from_file_location('ac_session',Path(__file__).parents[1]/'scripts/ac-offline-smoke.py')
session=importlib.util.module_from_spec(spec)
spec.loader.exec_module(session)


class SessionSafety(unittest.TestCase):
    def test_offline_grid_and_disabled_wheel_ffb(self):
        overlays,track,layout=session.build_overlays('keyboard','grid','drag2000')
        race=configparser.ConfigParser();race.read_string(overlays['race.ini'])
        controls=configparser.ConfigParser();controls.read_string(overlays['controls.ini'])
        self.assertEqual(race.getint('REMOTE','ACTIVE'),0)
        self.assertEqual(race.getint('REPLAY','ACTIVE'),0)
        self.assertEqual(race.getint('BENCHMARK','ACTIVE'),0)
        self.assertEqual(race.getint('SESSION_0','TYPE'),3)
        self.assertEqual(race['SESSION_0']['SPAWN_SET'],'START')
        self.assertEqual((race['RACE']['TRACK'],race['RACE']['CONFIG_TRACK']),(track,layout))
        self.assertEqual(controls.getfloat('STEER','FF_GAIN'),0)

    def test_unsupported_selection_refused_before_writes(self):
        for mode,start,track in [('keyboard','grid','../other'),('online','pit','magione'),
                                 ('benchmark','grid','drag2000')]:
            with self.assertRaises(ValueError):session.build_overlays(mode,start,track)
