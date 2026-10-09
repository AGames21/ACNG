import struct
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'converters'))
import build_ac_car  # noqa: E402
import export_kn5  # noqa: E402
import jbeam_io  # noqa: E402
import kn5_model  # noqa: E402


def u(n):
    return struct.pack('<I', n)


def s(text):
    data = text.encode()
    return u(len(data)) + data


IDENTITY = struct.pack('<16f', 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
SHIFTED = struct.pack('<16f', 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0.5, 0, 0, 1)


def fixture():
    # Entirely original synthetic triangle under a translated node, not a game asset.
    material = s('paint') + s('ksPerPixel') + bytes(6) + u(0) + u(0)
    verts = b''
    for x, y, z in ((0, 0, 0), (1, 0, 0), (0, 1, 0)):
        verts += struct.pack('<8f', x, y, z, 0, 0, 1, x, y) + bytes(12)
    mesh = u(2) + s('tri') + u(0) + b'\x01' + b'\x01\x01\x00'
    mesh += u(3) + verts + u(3) + struct.pack('<3H', 0, 1, 2) + u(0) + bytes(29)
    door = u(1) + s('DOOR_L') + u(1) + b'\x01' + SHIFTED + mesh
    root = u(1) + s('root') + u(1) + b'\x01' + IDENTITY + door
    return b'sc6969' + u(6) + u(0) + u(0) + u(1) + material + root


class KN5Model(unittest.TestCase):
    def test_world_space_geometry_and_parents(self):
        model = kn5_model.read(fixture())
        self.assertEqual(len(model['meshes']), 1)
        mesh = model['meshes'][0]
        self.assertEqual(mesh['path'], ['root', 'DOOR_L', 'tri'])
        self.assertEqual(mesh['positions'][1], (1.5, 0.0, 0.0))  # node translation applied
        self.assertEqual(mesh['indices'], [0, 1, 2])

    def test_truncated_or_trailing_data_refused(self):
        for data in (fixture()[:-1], fixture() + b'x', b'sc6969' + u(9)):
            with self.assertRaises(ValueError):
                kn5_model.read(data)


class JBeamIO(unittest.TestCase):
    def test_comments_missing_and_trailing_commas(self):
        text = '{"p": {// c\n "nodes": [["id","posX"] ["a" 1.5,], /* x */], "v": 2,}}'
        self.assertEqual(jbeam_io.loads(text), {'p': {'nodes': [['id', 'posX'], ['a', 1.5]], 'v': 2}})
        self.assertEqual(jbeam_io.loads(jbeam_io.dumps(jbeam_io.loads(text))), jbeam_io.loads(text))


def mesh(path, material='paint', positions=((0, 0, 1), (1, 0, 1), (0, 1, 1))):
    return {'name': path[-1], 'path': path, 'material': material, 'active': True, 'visible': True,
            'positions': list(positions), 'normals': [(0, 1, 0)] * 3, 'uvs': [(0, 0), (1, 0), (0, 1)],
            'indices': [0, 1, 2]}


MATS = {'paint': {'shader': 'ksPerPixel'}, 'DAMAGE_GLASS': {'shader': 'ksBrokenGlass'},
        'VETRI_Fanali': {'shader': 'ksPerPixel'}}


class Exporter(unittest.TestCase):
    def test_routing(self):
        self.assertEqual(export_kn5.route(mesh(['r', 'DOOR_L', 'x']), MATS), 'door_L')
        self.assertEqual(export_kn5.route(mesh(['r', 'COCKPIT_HR', 'DOOR_R1', 'x']), MATS), 'door_R')
        self.assertEqual(export_kn5.route(mesh(['r', 'WHEEL_LF', 'x']), MATS), export_kn5.SKIP)
        self.assertEqual(export_kn5.route(mesh(['r', 'x'], 'DAMAGE_GLASS'), MATS), export_kn5.SKIP)
        self.assertEqual(export_kn5.route(mesh(['r', 'x'], 'VETRI_Fanali'), MATS), 'lights_F')  # AC +z = front
        rear = mesh(['r', 'x'], 'VETRI_Fanali', ((0, 0, -2), (1, 0, -2), (0, 1, -2)))
        self.assertEqual(export_kn5.route(rear, MATS), 'lights_R')
        self.assertEqual(export_kn5.route(mesh(['r', 'x']), MATS), 'body')

    def test_frame_uv_and_winding(self):
        self.assertEqual(export_kn5.to_beamng((1, 2, 3), 0.5), (1, -3, 2.5))
        # Stored normal (AC +y = BeamNG +z) agrees with this winding after the frame change.
        m = mesh(['r', 'x'], positions=((0, 0, 0), (1, 0, 0), (0, 0, -1)))
        pos, nrm, uvs, tris, flipped = export_kn5.convert_mesh(m, 0)
        self.assertFalse(flipped)
        self.assertEqual(uvs[0], (0, 1.0))
        m['normals'] = [(0, -1, 0)] * 3
        self.assertTrue(export_kn5.convert_mesh(m, 0)[4])

    def test_collada_is_valid_xml_with_single_index_triangles(self):
        g = export_kn5.Group('acng_test_body')
        g.add('paint', [(0, 0, 0), (1, 0, 0), (0, 1, 0)], [(0, 0, 1)] * 3, [(0, 0)] * 3, [(0, 1, 2)])
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 't.dae'
            export_kn5.write_collada([g], p, {'paint': 'acng_test_paint'})
            root = ET.parse(p).getroot()
        ns = '{http://www.collada.org/2005/11/COLLADASchema}'
        tri = root.find(f'.//{ns}triangles')
        self.assertEqual(tri.get('material'), 'acng_test_paint')
        self.assertEqual({i.get('offset') for i in tri.findall(f'{ns}input')}, {'0'})
        self.assertEqual(root.find(f'.//{ns}up_axis').text, 'Z_UP')

    def test_only_beamng_readable_dds_kept_native(self):
        def dds(flags, fourcc, bits):
            return b'DDS ' + bytes(76) + struct.pack('<I4sI', flags, fourcc, bits) + bytes(36)
        self.assertTrue(export_kn5.dds_native(dds(0x4, b'DXT5', 0)))
        self.assertFalse(export_kn5.dds_native(dds(0x41, bytes(4), 32)))  # 32-bit ARGB, rejected in 0.39
        self.assertFalse(export_kn5.dds_native(dds(0x40, bytes(4), 24)))  # 24-bit RGB
        self.assertFalse(export_kn5.dds_native(dds(0x20001, bytes(4), 16)))  # luminance-alpha
        self.assertFalse(export_kn5.dds_native(dds(0x41, bytes(4), 16)))  # 4444
        self.assertFalse(export_kn5.dds_native(b'not a dds'))

    def test_refuses_output_inside_repo(self):
        with self.assertRaises(SystemExit):
            export_kn5.guard_output(export_kn5.REPO_ROOT / 'build' / 'car')
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(export_kn5.guard_output(d), Path(d).resolve())


class Builder(unittest.TestCase):
    PART = {
        'nodes': [['id', 'posX', 'posY', 'posZ'], {'nodeWeight': 1}, ['a', 0.5, -1.0, 1.3], ['b', 0.5, 1.0, 0.4]],
        'flexbodies': [['mesh', '[group]:'], ['etkc_body', ['g']], ['etkc_lowerarm_F_a', ['g']], ['licenseplate', ['g']],
                       ["$= $x and 'etkc_diffuser_R' or 'y'", ['g']], ['brake_hub_5l', ['g']]],
        'props': [['func', 'mesh', 'idRef:'], ['steering', 'etkc_steer', 'a'], ['lights', 'SPOTLIGHT', 'a']],
        'mirrors': [['mesh'], ['etkc_mirror_L']],
        'slots2': [['name', 'allowTypes', 'denyTypes', 'default', 'description'],
                   ['etkc_towhitch', ['etkc_towhitch'], [], '', 'Hitch', {'nodeOffset': {'x': 0, 'y': -0.44, 'z': 0}}],
                   ['wheel_F_5', ['wheel_F_5'], [], 'w', 'Wheels', {'nodeOffset': {'x': '$=$t', 'y': -1.295, 'z': 0.35}}]],
    }

    def test_transform_keeps_physics_and_strips_visible_etk_skin(self):
        part, report = build_ac_car.transform_part('etkc_body', self.PART, {'etkc_towhitch'}, {})
        a, b = part['nodes'][2], part['nodes'][3]
        self.assertAlmostEqual(a[2], build_ac_car.SY * -1.0 + build_ac_car.TY, places=5)
        self.assertAlmostEqual(a[3], 0.9 + 1.15 * 0.4, places=5)  # roof raised
        self.assertEqual(b[3], 0.4)  # below the knee: unchanged
        self.assertEqual(a[1], 0.5)  # width unchanged
        meshes = [r[0] for r in part['flexbodies'][1:]]
        self.assertEqual(meshes, ['etkc_lowerarm_F_a', 'brake_hub_5l'])
        self.assertEqual([r[1] for r in part['props'][1:]], ['SPOTLIGHT'])
        self.assertNotIn('mirrors', part)
        hitch, wheel = part['slots2'][1][-1]['nodeOffset'], part['slots2'][2][-1]['nodeOffset']
        self.assertAlmostEqual(hitch['y'], build_ac_car.SY * -0.44, places=5)  # local child: length only
        self.assertAlmostEqual(wheel['y'], build_ac_car.SY * -1.295 + build_ac_car.TY, places=5)  # common child
        self.assertEqual(wheel['x'], '$=$t')
        self.assertEqual(self.PART['nodes'][2][2], -1.0)  # input untouched

    def test_every_exported_group_has_a_flexbody_owner(self):
        targets = {'body', 'fender_L', 'fender_R', 'door_L', 'door_R', 'hood', 'bumper_F', 'bumper_R',
                   'lights_FL', 'lights_FR', 'lights_RL', 'lights_RR',
                   'trunk', 'dash', 'cabin', 'seat_L', 'seat_R', 'shifter', 'shifter_boot',
                   'nose'}  # 'nose' only receives far body triangles (car_upgrades.reroute_nose)
        self.assertEqual(set(build_ac_car.FLEXBODIES), targets)
        # One node group per outer panel: spanning groups stretched and tore the skin in crashes.
        for name in ('body', 'fender_L', 'fender_R', 'door_L', 'door_R', 'hood', 'trunk',
                     'lights_FL', 'lights_FR', 'lights_RL', 'lights_RR'):
            self.assertEqual(len(build_ac_car.FLEXBODIES[name][1]), 1, name)
        self.assertFalse(build_ac_car.strip_visible('etkc_lowerarm_F'))
        self.assertTrue(build_ac_car.strip_visible('etkc_tubs'))  # poked out of the 1M arch

    def test_kept_meshes_follow_their_moved_nodes(self):
        files = {'f': {'p': {'nodes': [['id', 'posX', 'posY', 'posZ'], {'group': 'ex'}, ['a', 0, 1.4, 0.3],
                                       ['b', 0, 1.6, 0.3, {'group': ['ex', 'tip']}], {'group': ''}, ['c', 0, 9, 9]]}}}
        c = build_ac_car.group_centroids(files)
        self.assertEqual(c['ex'], (1.5, 0.3))
        self.assertEqual(c['tip'], (1.6, 0.3))
        header = ['mesh', '[group]:', 'nonFlexMaterials']
        dy = build_ac_car.tf_y(1.5) - 1.5
        # In-place mesh with a small offset: shift by how far its nodes moved, not tf(offset).
        row = build_ac_car._move_flexbody(['exhaust', ['ex'], [], {'pos': {'x': 0, 'y': -0.11, 'z': 0.03}}], header, c)
        self.assertAlmostEqual(row[-1]['pos']['y'], -0.11 + dy, places=4)
        self.assertEqual(row[-1]['pos']['z'], 0.03)
        row = build_ac_car._move_flexbody(['tank', ['ex']], header, c)  # unplaced: gains a pos
        self.assertAlmostEqual(row[3]['pos']['y'], dy, places=4)
        # Wheel-bound brake disc authored at the origin: its pos is its location (C010 off-centre discs).
        row = build_ac_car._move_flexbody(['disc', ['wheel_FL'], [], {'pos': {'x': .76, 'y': -1.295, 'z': .351}}], header, c)
        self.assertAlmostEqual(row[-1]['pos']['y'], build_ac_car.tf_y(-1.295), places=4)
        self.assertEqual(build_ac_car._move_flexbody(['x', ['unknown']], header, c), ['x', ['unknown']])

    def test_debrand_fills_the_box_from_its_edges(self):
        import io
        from PIL import Image
        im = Image.new('RGB', (10, 4), (0, 0, 0))
        for y in range(4):
            im.putpixel((9, y), (90, 90, 90))
            for x in range(3, 7):
                im.putpixel((x, y), (255, 255, 255))  # the "logo"
        buf = io.BytesIO(); im.save(buf, 'PNG')
        out = Image.open(io.BytesIO(export_kn5._debrand(buf.getvalue(), [(0.3, 0, 0.7, 1)])))
        self.assertEqual(out.getpixel((5, 1)), (0, 0, 0))  # dark on both sides -> dark
        self.assertNotIn((255, 255, 255), [out.getpixel((x, 2)) for x in range(10)])


if __name__ == '__main__':
    unittest.main()
