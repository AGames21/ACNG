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
                          mat('VETRI_Texture', 'ksPerPixelReflection', 1, 'olive.png')],
            'textures': {'lamp.png': png((200, 200, 200)), 'red.png': png((225, 30, 30)),
                         'grey.png': png((90, 93, 90)), 'cap_nm.png': png((244, 59, 253), alpha=0),
                         'olive.png': png((29, 31, 10), alpha=125)},
            'meshes': [mesh('front_light_1', 'lamp'), mesh('brake_light_1', 'Fanali_POSTERIORI_TS', -2),
                       mesh('rear_light_1', 'Fanali_POSTERIORI_TS', -2), mesh('m', 'MIRROR', group='mirror_L'),
                       mesh('cap', 'cap'), mesh('glass', 'VETRI_Texture')]}
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
        self.assertEqual(report['glow']['t_Fanali_POSTERIORI_TS_taillight']['on'], 't_Fanali_POSTERIORI_TS_taillight_on')
        lit = mats['t_lamp_headlight_on']['Stages'][0]
        self.assertEqual(lit['emissiveIntensityNits'], 15000)
        self.assertTrue((out / lit['emissiveMap'][len('/vehicles/v/'):]).is_file())
        self.assertNotIn('emissiveFactor', mats['t_lamp_headlight']['Stages'][0])

    def test_unlit_red_lenses_are_dimmed(self):
        _, _, mats = self.export()
        self.assertEqual(mats['t_Fanali_POSTERIORI_TS_brakelight']['Stages'][0]['baseColorFactor'],
                         [export_kn5.UNLIT_LENS_FACTOR] * 3 + [1])
        self.assertNotIn('baseColorFactor', mats['t_Fanali_POSTERIORI_TS_brakelight_on']['Stages'][0])

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


if __name__ == '__main__':
    unittest.main()
