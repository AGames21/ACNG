import copy
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'converters'))
import car_upgrades as u
import export_kn5
import build_ac_car


class UpgradeContracts(unittest.TestCase):
    def mesh(self):
        return {'name':'seat','path':['ROOT','COCKPIT_HR','seat'],'material':'test',
                'active':True,'visible':True,
                'positions':[(.3,.7,-.2),(.4,.7,-.2),(.3,.8,-.2),
                             (-.3,.7,-.2),(-.4,.7,-.2),(-.3,.8,-.2)],
                'normals':[(0,0,1)]*6,'uvs':[(0,0)]*6,'indices':[0,1,2,3,4,5]}

    def test_islands_keep_all_triangles_and_separate_seats(self):
        m=self.mesh();pieces=list(u.components(m))
        self.assertEqual(len(pieces),2)
        self.assertEqual(sum(len(p['indices']) for p in pieces),len(m['indices']))
        self.assertEqual({u.interior_group(p,.016) for p in pieces},{'seat_L','seat_R'})

    def test_uv_seams_weld_into_one_island(self):
        m=self.mesh();m['positions'][3]=m['positions'][0]
        self.assertEqual(len(list(u.components(m))),1)

    def test_explicit_native_prop_frame_not_global_geometry(self):
        m=self.mesh();m['prop_frame']={'pivot':(.3,.2,.7),
            'axes':[(1,0,0),(0,1,0),(0,0,1)]}
        pos,_,_,_,_=export_kn5.convert_mesh(m,0)
        self.assertEqual(pos[0],(0,0,0))

    def test_prop_mounts_are_damage_attached_and_noncolliding(self):
        part={};frame={'pivot':[0,0,1],'axes':[(1,0,0),(0,1,0),(0,0,1)]}
        u.add_prop(part,'steer',frame,'test_')
        self.assertEqual(part['props'][1][0],'steering')
        self.assertEqual(part['props'][1][1],'test_steer')
        self.assertEqual(len([r for r in part['nodes'][1:] if isinstance(r,list)]),3)
        self.assertEqual(part['beams'][1]['beamStrength'],50000)
        self.assertFalse(part['nodes'][1]['collision'])
        # The DAE uses local origin zero. Without this, BeamNG retains model origin
        # at the car centre instead of positioning the control on its reference node.
        self.assertEqual(part['props'][1][-1]['baseTranslation'],{'x':0,'y':0,'z':0})
        self.assertEqual(part['props'][1][-1]['baseRotationGlobal']['x'],70)

    def test_front_structure_stays_at_donor_mounts_with_hidden_protruding_skin(self):
        self.assertAlmostEqual(build_ac_car.tf_y(-1),build_ac_car.SY*-1+build_ac_car.TY)
        part,_=build_ac_car.transform_part('etkc_bumper_F',{'nodes':[['id','posX','posY','posZ'],['b',0,-2.2,.5]]},set(),{})
        self.assertAlmostEqual(part['nodes'][1][2],build_ac_car.tf_y(-2.2),places=5)
        self.assertTrue(build_ac_car.strip_visible('etkc_bumperbar'))
        self.assertTrue(build_ac_car.strip_visible('etkc_radsupport'))

    def test_specs_and_baseline_are_independent(self):
        pc={'parts':{'etk_transmission':'original'},'vars':{'fuel':20}}
        saved=copy.deepcopy(pc);new=u.spec_config(pc)
        self.assertEqual(pc,saved)
        self.assertEqual(new['parts']['etk_finaldrive_R'],'etk_finaldrive_R_315')
        self.assertEqual(new['parts']['etkc_fueltank'],'acng_1m_fueltank')
        self.assertEqual(new['vars']['$fuel'],47.7)
        self.assertNotIn('$acngBodyMassScale',new['vars'])
        self.assertEqual(u.GEAR_RATIOS,[-3.727,0,4.110,2.315,1.542,1.179,1.000,.846])

    def test_seat_cages_have_independent_groups_and_breakable_beams(self):
        model,frames=u.prepare_model({'meshes':[self.mesh()]},.016)
        part={};u.add_seat_cages(part,model,.016,'test_')
        groups={r['group'] for r in part['nodes'] if isinstance(r,dict) and r.get('group')}
        self.assertEqual(groups,{'test_seat_L','test_seat_R'})
        self.assertEqual(len([r for r in part['nodes'] if isinstance(r,list) and len(r)==4]),17)

    def test_chassis_node_weights_remain_native(self):
        part,_=build_ac_car.transform_part('etkc_body',{'nodes':[['id','posX','posY','posZ'],{'nodeWeight':10},['b',0,0,1]]},set(),{})
        self.assertEqual(part['nodes'][1]['nodeWeight'],10)
        self.assertNotIn('variables',part)

    def test_spec_parts_do_not_mutate_donor_tank_or_engine(self):
        stock={'etk_engine_i6_3.0':{'mainEngine':{'torque':[['rpm','torque'],[3000,300]]}},
               'etk_transmission_6M_sport':{'gearbox':{'gearRatios':[0,1]}},
               'etkc_fueltank':{'mainTank':{'fuelCapacity':50},'variables':[['name'],['$fuel','range','L','Chassis',50,0,50]]}}
        original=copy.deepcopy(stock);parts=u.spec_parts(stock)
        self.assertEqual(stock,original)
        self.assertEqual(parts['acng_1m_fueltank']['mainTank']['fuelCapacity'],53)
        self.assertEqual(parts['acng_1m_fueltank']['variables'][1][4],47.7)


if __name__=='__main__': unittest.main()
