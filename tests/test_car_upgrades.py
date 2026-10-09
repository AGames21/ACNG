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
        self.assertEqual(part['props'][1][-1]['baseRotationGlobal']['x'],-70)

    def test_gauge_rest_rotation_uses_beamng_sign(self):
        part={};frame={'pivot':[0,0,1],'axes':[(1,0,0),(0,1,0),(0,0,1)],'rest_x':-84,
                       'func':'rpm','rate':.03,'min':0,'max':8000,'offset':0}
        u.add_prop(part,'gauge_rpm',frame,'test_')
        self.assertEqual(part['props'][1][-1]['baseRotationGlobal']['x'],84)

    def test_cosmetic_mounts_are_damped_not_ringing(self):
        import math
        for kg,spring,damp in ((u.PROP_NODE_KG,u.PROP_SPRING,u.PROP_DAMP),):
            ratio=damp/(2*math.sqrt(spring*kg))
            self.assertGreater(ratio,.08)   # old cages were ~2%: visible wobble
            self.assertLess(.0005*math.sqrt(10*spring/kg),1)  # explicit step stays stable
        part={};u.add_prop(part,'steer',{'pivot':[0,0,1],'axes':[(1,0,0),(0,1,0),(0,0,1)]},'t_')
        self.assertEqual(part['nodes'][1]['nodeWeight'],u.PROP_NODE_KG)
        self.assertEqual(part['beams'][1]['beamDamp'],u.PROP_DAMP)

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

    def piece(self,material,lo,hi):
        # BeamNG-frame box -> AC positions (x, z-lift, -y)
        pts=[(x,z-.016,-y) for x in (lo[0],hi[0]) for y in (lo[1],hi[1]) for z in (lo[2],hi[2])]
        return {'material':material,'positions':pts}

    def test_only_seat_shells_ride_the_native_seat_nodes(self):
        # Measured 1M pieces: seat back, then the sill trim, belt and rear-panel fabric that
        # used to be classed as seat and jiggled on cosmetic cages.
        self.assertEqual(u.interior_group(self.piece('INT_Skin',(.09,.2,.4),(.64,.55,1.01)),.016),'seat_L')
        self.assertEqual(u.interior_group(self.piece('INT_Skin',(-.64,.2,.4),(-.09,.55,1.01)),.016),'seat_R')
        for material,lo,hi in (('INT_Plaastica_NERA',(.64,-.58,.38),(.75,.55,1.03)),
                               ('LIVREA',(.7,-.71,.31),(.86,.61,1.1)),
                               ('INT_CintureSicurezza',(.61,.48,.3),(.67,.66,1.1)),
                               ('INT_Velluto',(.62,.64,.79),(.66,1.02,.93))):
            self.assertEqual(u.interior_group(self.piece(material,lo,hi),.016),'cabin',material)
        self.assertFalse(hasattr(u,'add_seat_cages'))
        self.assertEqual(build_ac_car.FLEXBODIES['seat_L'],('etkc_seat_FL',['etkc_floor','etkc_seat_FL']))

    def test_steering_frame_uses_the_ac_column_node(self):
        # 1M STEER_HR: column tilted 22 degrees, pointing forward and down toward the rack.
        c,s=0.9271838665008545,0.37460657954216003
        model={'nodes':[{'name':'STEER_HR','world':[[1,0,0,0],[0,c,s,0],[0,-s,c,0],[.36,.86,.28,1]]}],
               'meshes':[dict(self.mesh(),path=['ROOT','COCKPIT_HR','STEER_HR','w'])]}
        _,frames=u.prepare_model(model,.016)
        frame=frames['steer']
        self.assertEqual(frame['pivot'],[.36,-.28,.86+.016])
        axis=frame['axes'][2]
        self.assertLess(axis[1],-.9)  # forward
        self.assertLess(axis[2],-.3)  # and down, not up as the old fixed frame assumed
        self.assertAlmostEqual(frame['rest_x'],112.0,delta=.1)
        part={};u.add_prop(part,'steer',frame,'t_')
        self.assertAlmostEqual(part['props'][1][-1]['baseRotationGlobal']['x'],-112.0,delta=.1)
        # without the node, the old fixed frame still works
        _,frames=u.prepare_model({'meshes':model['meshes']},.016)
        self.assertEqual(u.prop_rest_x('steer',frames['steer']),-70)

    def test_fender_triangles_leave_the_body_shell(self):
        def tri(x,y,z):  # one BeamNG-frame triangle as AC positions
            return [(x,z-.016,-y),(x,z-.016+.01,-y),(x,z-.016,-y-.01)]
        pos=tri(.8,-1.2,.6)+tri(-.8,-1.2,.6)+tri(.8,1.0,.6)+tri(.3,-1.2,.95)+tri(-.9,2.2,.5)+tri(.9,-1.9,1.2)
        shell={'name':'shell','path':['ROOT','shell'],'material':'LIVREA','positions':pos,
               'normals':[(0,1,0)]*len(pos),'uvs':[(0,0)]*len(pos),'indices':list(range(len(pos)))}
        out=u.split_fenders({'meshes':[shell]},.016,lambda m:True)['meshes']
        groups={m['name']:(m.get('acng_group'),len(m['indices'])//3) for m in out}
        self.assertEqual(groups,{'shell_fender_L':('fender_L',1),'shell_fender_R':('fender_R',1),
                                 'shell_body':(None,4)})
        self.assertEqual(sum(len(m['indices']) for m in out),len(shell['indices']))

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
