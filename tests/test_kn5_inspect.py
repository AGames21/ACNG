import struct
import unittest
from converters.inspect_kn5 import inspect


def u(n):
    return struct.pack('<I', n)


def s(text):
    data = text.encode()
    return u(len(data)) + data


def fixture():
    material = s('synthetic') + s('shader') + bytes(6) + u(0) + u(0)
    # Entirely original synthetic triangle, not a game asset.
    mesh = u(2) + s('triangle') + u(0) + b'\x01' + bytes(3)
    mesh += u(3) + bytes(3 * 44) + u(3) + struct.pack('<3H', 0, 1, 2) + u(0) + bytes(29)
    root = u(1) + s('root') + u(1) + b'\x01' + bytes(64) + mesh
    return b'sc6969' + u(6) + u(0) + u(0) + u(1) + material + root


class KN5Contracts(unittest.TestCase):
    def test_synthetic_mesh_complete_and_non_exporting(self):
        result = inspect(fixture())
        self.assertEqual(result['mesh_count'], 1)
        self.assertEqual(result['triangles'], 1)
        self.assertFalse(result['exports_game_assets'])
        self.assertFalse(result['driveable_vehicle'])

    def test_truncation_signature_version_and_trailing_data_refused(self):
        for data in (fixture()[:-1], b'badmagic', fixture() + b'junk', b'sc6969' + u(99)):
            with self.assertRaises(ValueError):
                inspect(data)


if __name__ == '__main__':
    unittest.main()
