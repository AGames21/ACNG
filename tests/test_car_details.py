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

    def test_rims_declare_the_track_the_config_sets(self):
        donor={'information':{},'flexbodies':[['mesh','[group]:','nonFlexMaterials'],
               ['a',['wheel_FL'],[],{'pos':{'x':.51}}],['b',['wheel_FR'],[],{'pos':{'x':-.51}}]]}
        rear=copy.deepcopy(donor)
        for row in rear['flexbodies'][1:]: row[-1]['pos']['x']=.5 if row[-1]['pos']['x']>0 else -.5
        parts=d.wheel_parts({'etk_wheel_08a_19x9_F':donor,'etk_wheel_08a_19x10_R':rear},'p_')
        vars=d.wheel_config({'parts':{}})['vars']
        for axle in 'FR':
            part=parts['acng_1m_wheel_'+axle];head,decl=part['variables']
            row=dict(zip(head,decl))
            # BeamNG ignores (and clamps) .pc vars that no part declares.
            self.assertEqual(row['name'],'$trackwidth_'+axle)
            self.assertTrue(row['min']<=vars[row['name']]<=row['max'])
            self.assertEqual(row['default'],vars[row['name']])
            rows=part['flexbodies'][1:]
            self.assertAlmostEqual(vars[row['name']]+rows[0][-1]['pos']['x'],.754,places=2)
            self.assertAlmostEqual(-vars[row['name']]+rows[1][-1]['pos']['x'],-.754,places=2)

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

    def test_native_eu_plate_replaces_the_branded_ac_plate(self):
        part = d.plate_part()['acng_1m_licenseplate_R']
        self.assertEqual(part['slotType'], 'etkc_licenseplate_R')
        mesh, groups, _, opts = part['flexbodies'][1]
        self.assertTrue(mesh.startswith('licenseplate-'))  # native BeamNG plate mesh
        self.assertEqual(groups, ['etkc_trunk'])
        self.assertEqual(opts['rot']['z'], 180)  # faces rearward
        self.assertEqual(export_kn5.route(dict(self.mesh(['ROOT']), name='Plate_LODA'), {'test': {'shader': 'ksPerPixel'}}), export_kn5.SKIP)

    def test_brakes_are_1m_sized_drilled_discs_with_single_piston_calipers(self):
        def donor(disc):
            opts = lambda: {'pos': {'x': .76, 'y': -1.326, 'z': .351}, 'scale': {'x': 1.3, 'y': 1.14, 'z': 1.14},
                            'rot': {'x': 180, 'y': 0, 'z': 0}}
            return {'flexbodies': [['mesh', '[group]:', 'nonFlexMaterials'], [disc, ['wheel_FL'], [], opts()],
                                   ['brake_caliper_6pot_blue', ['etkc_hub_F'], [], opts()], ['brake_hub_5l', ['wheel_FL'], [], opts()]],
                    'pressureWheels': [['name'], {'brakeDiameter': 0.37}, {'brakeTorque': 3000}]}
        stock = {'etkc_brake_F_tt': donor('brake_disc_plain'), 'etkc_brake_R_tt': donor('brake_disc_drilled')}
        parts = d.brake_parts(stock)
        for axle, size, scale in (('F', 0.36, 1.10), ('R', 0.35, 1.06)):
            p = parts['acng_1m_brake_'+axle]
            rows = {r[0]: r[-1] for r in p['flexbodies'][1:]}
            self.assertEqual(set(rows), {'brake_disc_drilled', 'brake_caliper_standard_red', 'brake_hub_5l'})
            self.assertEqual(rows['brake_disc_drilled']['scale']['y'], scale)
            self.assertEqual(rows['brake_disc_drilled']['pos'], {'x': .76, 'y': -1.326, 'z': .351})  # kept centred
            self.assertIn({'brakeDiameter': size}, p['pressureWheels'])
            self.assertIn({'brakeTorque': 3000}, p['pressureWheels'])
        self.assertEqual(parts['acng_1m_brake_F']['flexbodies'][1][-1]['rot']['y'], 180)  # plain -> drilled
        self.assertEqual(parts['acng_1m_brake_R']['flexbodies'][1][-1]['rot']['y'], 0)
        self.assertEqual(stock['etkc_brake_F_tt']['flexbodies'][1][0], 'brake_disc_plain')  # donor untouched


if __name__ == '__main__': unittest.main()
