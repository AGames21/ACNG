import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'converters'))
import export_kn5  # noqa: E402

try:
    from PIL import Image
except ImportError:  # the converter itself needs Pillow; plain test runs may not
    Image = None


def png(colour, size=(4, 4), alpha=None):
    im = Image.new('RGBA', size, colour + (255,))
    if alpha is not None:
        im.putalpha(Image.new('L', size, alpha))
        im.putpixel((0, 0), colour + (255,))  # cutout: some opaque, mostly clear
    buf = io.BytesIO()
    im.save(buf, 'PNG')
    return buf.getvalue()


def flat_png(rgba, size=(4, 4)):
    buf = io.BytesIO()
    Image.new('RGBA', size, rgba).save(buf, 'PNG')
    return buf.getvalue()


def tail_png():
    """Red lens texels with one grey reflector texel at (0, 0)."""
    im = Image.new('RGB', (2, 2), (250, 10, 10))
    im.putpixel((0, 0), (180, 180, 180))
    buf = io.BytesIO()
    im.save(buf, 'PNG')
    return buf.getvalue()


def mat(name, shader='ksPerPixel', blend=0, diffuse=None, normal=None):
    textures = {'txDiffuse': diffuse} if diffuse else {}
    if normal:
        textures['txNormal'] = normal
    return {'name': name, 'shader': shader, 'blend': blend, 'alpha_test': False,
            'props': {'ksSpecular': 0.2}, 'textures': textures}


def mesh(name, material, z=2.0, group=None):
    m = {'name': name, 'path': ['root', name], 'material': material, 'active': True, 'visible': True,
         'positions': [(0, 0, z), (1, 0, z), (0, 1, z)], 'normals': [(0, 0, 1)] * 3,
         'uvs': [(0, 0), (1, 0), (0, 1)], 'indices': [0, 1, 2]}
    if group:
        m['acng_group'] = group
    return m


@unittest.skipIf(Image is None, 'Pillow not installed')
class Materials(unittest.TestCase):
    def export(self):
        model = {
            'materials': [mat('lamp', diffuse='lamp.png'),
                          mat('Fanali_POSTERIORI_TS', diffuse='red.png'),
                          mat('MIRROR'),
                          mat('cap', 'ksPerPixelNM', 1, 'grey.png', 'cap_nm.png'),
                          mat('VETRI_Texture', 'ksPerPixelReflection', 1, 'olive.png'),
                          mat('Fanali_POSTERIORI_OS', 'ksPerPixelMultiMap', 0, 'tail.png', 'tail_OS.png')],
            'textures': {'lamp.png': png((200, 200, 200)), 'red.png': png((225, 30, 30)),
                         'grey.png': png((90, 93, 90)), 'cap_nm.png': png((244, 59, 253), alpha=0),
                         'olive.png': png((29, 31, 10), alpha=125), 'tail.png': tail_png(),
                         'tail_OS.png': png((128, 128, 255))},
            'meshes': [mesh('front_light_2', 'lamp'), mesh('front_light_1', 'lamp'), mesh('front_light_3', 'lamp'),
                       mesh('brake_light_1', 'Fanali_POSTERIORI_TS', -2),
                       mesh('rear_light_1', 'Fanali_POSTERIORI_TS', -2), mesh('m', 'MIRROR', group='mirror_L'),
                       mesh('cap', 'cap'), mesh('glass', 'VETRI_Texture'),
                       mesh('polymsh263_SUB0', 'Fanali_POSTERIORI_OS', -2), mesh('rear_light_2', 'Fanali_POSTERIORI_OS', -2)]}
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        out = Path(self.tmp.name)
        report = export_kn5.export(model, out, 'v', 't_', 0)
        mats = json.loads((out / 'main.materials.json').read_text())
        return out, report, mats

    def test_lamps_get_native_glow_functions_and_emissive_on_state(self):
        out, report, mats = self.export()
        self.assertEqual(report['glow']['t_lamp_headlight']['simpleFunction'], {'lowbeam': 0.49, 'highbeam': 1})
        self.assertEqual(report['glow']['t_Fanali_POSTERIORI_TS_brakelight']['simpleFunction'], {'brakelights': 0.49})
        # 1M headlamp split (C016): rings are DRL/position lights, the inner lamp is high beam only.
        self.assertEqual(report['glow']['t_lamp_position']['simpleFunction'], {'drl': 1, 'lowhighbeam': 1})
        self.assertEqual(report['glow']['t_lamp_highbeam']['simpleFunction'], {'highbeam': 1})
        self.assertEqual(report['glow']['t_Fanali_POSTERIORI_TS_taillight']['on'], 't_Fanali_POSTERIORI_TS_taillight_on')
        lit = mats['t_lamp_headlight_on']['Stages'][0]
        self.assertEqual(lit['emissiveIntensityNits'], 15000)
        self.assertTrue((out / lit['emissiveMap'][len('/vehicles/v/'):]).is_file())
        self.assertNotIn('emissiveFactor', mats['t_lamp_headlight']['Stages'][0])

    def test_brake_lamps_are_intense_and_tail_lamps_dim(self):
        _, report, mats = self.export()
        brake, tail = report['glow']['t_Fanali_POSTERIORI_TS_brakelight'], report['glow']['t_Fanali_POSTERIORI_TS_taillight']
        self.assertEqual(brake['on'], 't_Fanali_POSTERIORI_TS_brakelight_on_intense')
        self.assertEqual(brake['on_intense'], brake['on'])
        self.assertEqual(tail['on'], 't_Fanali_POSTERIORI_TS_taillight_on')
        nits = lambda key: mats[key]['Stages'][0]['emissiveIntensityNits']
        self.assertGreaterEqual(nits(brake['on']), 3 * nits(tail['on']))
        head = report['glow']['t_lamp_headlight']
        self.assertGreater(nits(head['on_intense']), nits(head['on']))  # high beam brighter

    def test_red_lens_glow_keeps_texture_pattern(self):
        im = Image.new('RGB', (2, 1))
        im.putdata([(255, 0, 0), (235, 0, 0)])
        buf = io.BytesIO()
        im.save(buf, 'PNG')
        with Image.open(io.BytesIO(export_kn5._pattern_png(buf.getvalue(), (255, 18, 8)))) as out:
            bright, dim = out.getpixel((0, 0)), out.getpixel((1, 0))
        self.assertEqual(bright, (255, 18, 8))
        self.assertLess(dim[0], bright[0] / 2)
        self.assertGreater(dim[0], 0)

    def test_unlit_red_lenses_are_dimmed(self):
        _, _, mats = self.export()
        self.assertEqual(mats['t_Fanali_POSTERIORI_TS_brakelight']['Stages'][0]['baseColorFactor'],
                         [export_kn5.UNLIT_LENS_FACTOR] * 3 + [1])
        self.assertNotIn('baseColorFactor', mats['t_Fanali_POSTERIORI_TS_brakelight_on_intense']['Stages'][0])

    def test_tail_lens_with_normal_map_gets_shaded_red_and_chrome_reflectors(self):
        out, report, mats = self.export()
        stage = mats['t_Fanali_POSTERIORI_OS']['Stages'][0]
        self.assertNotIn('baseColorFactor', stage)
        self.assertNotIn('roughnessFactor', stage)
        self.assertEqual(stage['metallicFactor'], 1)
        read = lambda key: Image.open(out / stage[key][len('/vehicles/v/'):])
        with read('baseColorMap') as b, read('metallicMap') as m, read('roughnessMap') as r:
            lens, chrome = b.getpixel((1, 1)), b.getpixel((0, 0))
            self.assertLess(lens[0], 160)  # deep red, not the AC near-flat 250
            self.assertGreater(lens[0], 4 * lens[1])
            self.assertEqual(chrome, (180, 180, 180))
            self.assertEqual((m.getpixel((0, 0)), m.getpixel((1, 1))), (255, 0))
            self.assertLess(r.getpixel((0, 0)), r.getpixel((1, 1)))
        lit = mats[report['glow']['t_Fanali_POSTERIORI_OS_taillight']['on']]['Stages'][0]
        self.assertEqual(lit['baseColorMap'], stage['baseColorMap'])
        with Image.open(out / lit['emissiveMap'][len('/vehicles/v/'):]) as g:
            self.assertGreater(g.getpixel((1, 1))[0], 10 * g.getpixel((0, 0))[0])

    def test_lens_shade_follows_normal_map_relief(self):
        lit, tilted = png((128, 128, 255)), png((255, 128, 128))
        flat = export_kn5._lens_shade(tail_png(), lit)
        side = export_kn5._lens_shade(tail_png(), tilted)
        self.assertEqual(len(flat), 4)
        self.assertGreater(flat[0], side[0])

    def test_mirror_uses_vanilla_reflective_material(self):
        out, _, mats = self.export()
        self.assertNotIn('mirror', mats)
        self.assertIn('material="mirror"', (out / 't.dae').read_text())

    def test_normal_map_alpha_cutout_replaces_solid_diffuse_alpha(self):
        out, _, mats = self.export()
        stage = mats['t_cap']['Stages'][0]
        self.assertNotIn('normalMap', stage)
        with Image.open(out / stage['opacityMap'][len('/vehicles/v/'):]) as im:
            self.assertEqual(im.getextrema(), (0, 255))

    def test_cabin_glass_keeps_opacity_but_loses_green_tint(self):
        out, _, mats = self.export()
        stage = mats['t_VETRI_Texture']['Stages'][0]
        with Image.open(out / stage['baseColorMap'][len('/vehicles/v/'):]) as im:
            r, g, b = im.convert('RGB').getpixel((1, 1))
        self.assertEqual(r, g)
        self.assertEqual(g, b)
        self.assertIn('opacityMap', stage)


    def test_paint_layer_matches_vanilla_and_keeps_baked_shading(self):
        skin = Image.new('RGBA', (40, 4), (240, 240, 240, 0))  # paint: white with baked shading
        skin.putpixel((5, 1), (120, 120, 120, 0))  # a panel line under the paint
        for x in range(30, 40):
            for y in range(4):
                skin.putpixel((x, y), (20, 30, 40, 255))  # black trim
        buf = io.BytesIO()
        skin.save(buf, 'PNG')
        model = {'materials': [mat('LIVREA', 'ksPerPixelMultiMap', 0, 'skin.png')],
                 'textures': {'skin.png': buf.getvalue()}, 'meshes': [mesh('body', 'LIVREA')]}
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            export_kn5.export(model, out, 'v', 't_', 0)
            paint, trim = json.loads((out / 'main.materials.json').read_text())['t_LIVREA']['Stages'][:2]
            self.assertNotIn('roughnessFactor', paint)  # the paint preset sets roughness
            self.assertEqual(paint['detailNormalMap'], '/vehicles/common/orange_peel_n.normal.png')
            with Image.open(out / paint['ambientOcclusionMap'][len('/vehicles/v/'):]) as ao:
                self.assertEqual((ao.getpixel((0, 0)), ao.getpixel((5, 1)), ao.getpixel((35, 1))), (240, 120, 255))
            with Image.open(out / trim['baseColorMap'][len('/vehicles/v/'):]) as base:
                # trim colour grown under the paint edge, so filtering blends no white into the trim
                self.assertEqual(base.convert('RGB').getpixel((25, 1)), (20, 30, 40))
                self.assertEqual(base.convert('RGB').getpixel((0, 0)), (20, 30, 40))
            with Image.open(out / trim['opacityMap'][len('/vehicles/v/'):]) as op:
                self.assertEqual((op.getpixel((0, 0)), op.getpixel((35, 1))), (0, 255))

    def test_detail_only_multimap_uses_tiled_detail_not_white_diffuse(self):
        # M3 seats/roof: white diffuse with alpha ~0 shows only the tiled leather/carbon detail.
        carbon = mat('INT_carbon', 'ksPerPixelMultiMap', 0, 'base.png', 'flat_nm.png')
        carbon['textures']['txDetail'] = 'carbon.png'
        carbon['props'].update(useDetail=1.0, detailUVMultiplier=2.0)
        chassis = mat('CAR_chassis', 'ksPerPixelMultiMap', 0, 'skin.png')
        chassis['textures']['txDetail'] = 'flake.png'
        chassis['props'].update(useDetail=1.0, detailUVMultiplier=20.0)
        model = {'materials': [carbon, chassis, mat('CAR_stencil', 'ksPerPixelNM', 1, 'flake.png', 'ring_nm.png')],
                 'textures': {'base.png': flat_png((255, 255, 255, 1)), 'flat_nm.png': png((128, 128, 255)),
                              'carbon.png': png((26, 26, 26)), 'skin.png': png((240, 240, 240), alpha=0),
                              'flake.png': png((234, 234, 234), alpha=100), 'ring_nm.png': png((128, 128, 255))},
                 'meshes': [mesh('roof', 'INT_carbon'), mesh('body', 'CAR_chassis'), mesh('pdc', 'CAR_stencil')]}
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            report = export_kn5.export(model, out, 'v', 't_', 0, paint_material='CAR_chassis')
            mats = json.loads((out / 'main.materials.json').read_text())
            dae = (out / 't.dae').read_text()
        self.assertEqual(report['detail_bakes'], {'INT_carbon': 2.0})  # the paint keeps its own path
        roof = mats['t_INT_carbon']['Stages'][0]
        self.assertEqual(roof['baseColorMap'], '/vehicles/v/textures/carbon.png')
        self.assertNotIn('baseColorFactor', roof)
        self.assertNotIn('normalMap', roof)
        self.assertIn('0 1 2 1 0 -1', dae)  # AC UVs x 2, then V flipped: (1, 0) -> (2, 1), (0, 1) -> (0, -1)
        # Parking-sensor discs: opaque body paint keeping the ring normal map, not white flake noise.
        self.assertEqual(report['paint_stencils'], ['CAR_stencil'])
        pdc = mats['t_CAR_stencil']
        self.assertTrue(pdc['Stages'][0]['instanceDiffuse'])
        self.assertEqual(pdc['Stages'][0]['normalMap'], '/vehicles/v/textures/ring_nm.png')
        self.assertNotIn('translucent', pdc)
        self.assertNotIn('opacityMap', pdc['Stages'][0])

    def test_worn_seat_belt_is_skipped_even_inside_cabin_group(self):
        belt = mesh('CINTURE_ON_SUB0', 'INT_belt', group='cabin')
        belt['path'] = ['root', 'COCKPIT_HR', 'CINTURE_ON', 'CINTURE_ON_SUB0']
        self.assertEqual(export_kn5.route(belt, {'INT_belt': mat('INT_belt')}), export_kn5.SKIP)
        belt['path'] = ['root', 'COCKPIT_HR', 'CINTURE_OFF', 'CINTURE_OFF_SUB2']
        self.assertEqual(export_kn5.route(belt, {'INT_belt': mat('INT_belt')}), 'cabin')

    def test_solid_glow_maps_are_at_least_16_px(self):
        with Image.open(io.BytesIO(export_kn5._solid_png((255, 0, 0)))) as im:
            self.assertGreaterEqual(min(im.size), 16)


if __name__ == '__main__':
    unittest.main()
