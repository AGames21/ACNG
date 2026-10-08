import copy
import math
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'converters'))
import car_details as d
import car_upgrades
import export_kn5


class DetailContracts(unittest.TestCase):
    def mesh(self, path, material='test'):
        return {'name': 'synthetic', 'path': path+['synthetic'], 'material': material,
                'active': True, 'visible': True, 'positions': [(1,2,3),(1.01,2,3),(1,2.01,3)],
                'normals': [(0,0,1)]*3, 'uvs': [(0,0)]*3, 'indices': [0,1,2]}

    def test_gauge_uses_node_pivot_not_needle_bbox(self):
        path=['ROOT','COCKPIT_HR','ARROW_SPEED']
        matrix=[[1,0,0,0],[0,1,0,0],[0,0,1,0],[1,2,3,1]]
        mesh=self.mesh(path)
        model={'nodes':[{'path':path,'world':matrix}], 'meshes':[mesh]}
        original=copy.deepcopy(model)
        prepared, frames, mirrors=d.prepare(model,.016)
        self.assertEqual(model,original)
        self.assertEqual(frames['gauge_speed']['pivot'],(1,-3,2.016))
        self.assertEqual(prepared['meshes'][0]['acng_group'],'gauge_speed')
        self.assertEqual(export_kn5.route(prepared['meshes'][0],{'test':{'shader':'ksPerPixel'}}),'gauge_speed')
        part={};car_upgrades.add_prop(part,'gauge_speed',frames['gauge_speed'],'local_')
        self.assertEqual(part['props'][1][0],'wheelspeed')
        self.assertAlmostEqual(part['props'][1][6]['z']*(300/3.6),256)
        self.assertEqual(part['props'][1][-1]['baseTranslation'],{'x':0,'y':0,'z':0})
        self.assertEqual(mirrors,{})

    def test_rim_override_keeps_tire_and_blur_excluded(self):
        wheel=['ROOT','WHEEL_LF']; matrix=[[1,0,0,0],[0,1,0,0],[0,0,1,0],[1,2,3,1]]
        model={'nodes':[{'path':wheel,'world':matrix}], 'meshes':[
            self.mesh(wheel+['RIM_LF']),self.mesh(wheel+['RIM_BLUR_LF']),self.mesh(wheel+['TYRE_LF'])]}
        prepared,_,_=d.prepare(model,0)
        self.assertEqual([export_kn5.route(m,{'test':{'shader':'ksPerPixel'}}) for m in prepared['meshes']],
                         ['rim_FL','skip','skip'])
        positions,_,_,_,_=export_kn5.convert_mesh(prepared['meshes'][0],0)
        self.assertEqual(positions[0],(0,0,0))

    def test_wheel_clone_preserves_all_physics_tables(self):
        donor={'information':{},'nodes':[['id'],['node',1,2,3]],'beams':[['a','b']],
               'pressureWheels':[{'hasTire':False}], 'slots':[['type'],['tire','stock']],
               'flexbodies':[['mesh','[group]:','nonFlexMaterials'],
                            ['donor',['wheel_FR','wheelhub_FR'],[],{'pos':{'x':-.51},'rot':{'z':180},'scale':{'x':1}}]]}
        stock={'etk_wheel_08a_19x9_F':donor,'etk_wheel_08a_19x10_R':copy.deepcopy(donor)}
        original=copy.deepcopy(stock);parts=d.wheel_parts(stock,'local_')
        self.assertEqual(stock,original)
        for name,part in parts.items():
            for key in ('nodes','beams','pressureWheels','slots'):
                self.assertEqual(part[key],donor[key])
        self.assertEqual(parts['acng_1m_wheel_F']['flexbodies'][1][0],'local_rim_FR')

    def test_mirror_centers_are_offsets_from_native_refs(self):
        files={'x':{'etkc_mirror_L':{'nodes':[['id','x','y','z'],['mi4l',1,2,3]]}}}
        d.add_mirrors(files,{'mirror_L':[1.1,2.2,3.3]},'local_')
        p=files['x']['etkc_mirror_L'];row=p['mirrors'][1]
        self.assertEqual(row[:4],['local_mirror_L','mi4l','mi3l','mi2l'])
        self.assertEqual(row[-1]['refBaseTranslation'],{'x':.1,'y':.2,'z':.3})
        self.assertNotIn('offsetRotationGlobal',row[-1])

    def test_mirror_atlas_uvs_fill_one_native_render_target(self):
        mesh=self.mesh(['ROOT','DOOR_L'],'MIRROR')
        mesh['uvs']=[(.62,-1),(.998,-1),(.62,0)]
        model,_,centers=d.prepare({'nodes':[], 'meshes':[mesh]},0)
        self.assertIn('mirror_L',centers)
        self.assertEqual(model['meshes'][0]['uvs'],[(0,0),(1,0),(0,1)])
        self.assertEqual(mesh['uvs'][0],(.62,-1))


if __name__ == '__main__': unittest.main()
