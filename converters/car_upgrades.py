"""Original local BMW 1M fitting/rigging helpers; contains no extracted assets."""
import copy
import math

GEAR_RATIOS = [-3.727, 0, 4.110, 2.315, 1.542, 1.179, 1.000, 0.846]
FINAL_DRIVE = 3.154
PROP_HEADER = ['func', 'mesh', 'idRef:', 'idX:', 'idY:', 'baseRotation', 'rotation',
               'translation', 'min', 'max', 'offset', 'multiplier']


def components(mesh):
    """Triangle islands with position welding across UV/material vertex seams."""
    parent = list(range(len(mesh['positions'])))
    def root(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    def join(a, b):
        parent[root(a)] = root(b)
    welded = {}
    for i, p in enumerate(mesh['positions']):
        key = tuple(round(c, 5) for c in p)
        if key in welded:
            join(i, welded[key])
        welded[key] = i
    triangles = [mesh['indices'][i:i+3] for i in range(0, len(mesh['indices']), 3)]
    for a, b, c in triangles:
        join(a, b); join(a, c)
    islands = {}
    for tri in triangles:
        islands.setdefault(root(tri[0]), []).extend(tri)
    for index, inds in enumerate(islands.values()):
        unique = sorted(set(inds)); remap = {v: i for i, v in enumerate(unique)}
        part = dict(mesh, name=mesh['name'] + '_piece' + str(index))
        part['path'] = mesh['path'][:-1] + [part['name']]
        for key in ('positions', 'normals', 'uvs'):
            part[key] = [mesh[key][i] for i in unique]
        part['indices'] = [remap[i] for i in inds]
        yield part


def bounds(points):
    return ([min(p[k] for p in points) for k in range(3)],
            [max(p[k] for p in points) for k in range(3)])


def interior_group(mesh, lift):
    points = [(p[0], -p[2], p[1]+lift) for p in mesh['positions']]
    low, high = bounds(points)
    x, y, z = [(low[k]+high[k])/2 for k in range(3)]
    if mesh['material'] == 'INT_Pedali' or (low[0] > 0.2 and high[0] < 0.7 and high[1] < -0.5 and high[2] < 0.54):
        return 'pedal_throttle' if x < 0.37 else 'pedal_brake' if x < 0.52 else 'pedal_clutch'
    if -0.13 < y < 0.85 and abs(x) > 0.17 and z > 0.46 and high[2] < 1.2:
        return 'seat_L' if x > 0 else 'seat_R'
    return 'dash' if y < -0.27 and z > 0.57 else 'cabin'


def prepare_model(model, lift):
    meshes = []
    for mesh in model['meshes']:
        path = mesh['path'][:-1]
        if 'COCKPIT_HR' in path and not any(p.startswith(('DOOR_', 'ARROW_', 'STEER_')) for p in path):
            if any(p.startswith('SHIFT_HR') for p in path):
                mesh = dict(mesh, acng_group='shifter')
                meshes.append(mesh)
            elif 'GEO_Guaina_Cambio' in path:
                meshes.append(dict(mesh, acng_group='shifter_boot'))
            else:
                for part in components(mesh):
                    part['acng_group'] = interior_group(part, lift)
                    meshes.append(part)
        else:
            meshes.append(mesh)
    frames = {}
    for name in ('steer', 'pedal_throttle', 'pedal_brake', 'pedal_clutch'):
        selected = [m for m in meshes if m.get('acng_group') == name or
                    (name == 'steer' and 'STEER_HR' in m['path'])]
        if not selected:
            continue
        points = [(p[0], -p[2], p[1]+lift) for m in selected for p in m['positions']]
        low, high = bounds(points)
        pivot = [(low[k]+high[k])/2 for k in range(3)]
        if name == 'steer':
            angle = math.radians(20)
            axes = [(1, 0, 0), (0, math.sin(angle), math.cos(angle)),
                    (0, -math.cos(angle), math.sin(angle))]
        else:
            pivot[2] = high[2]+0.025
            axes = [(1, 0, 0), (0, 1, 0), (0, 0, 1)]
        frame = {'pivot': pivot, 'axes': axes}
        frames[name] = frame
        for m in selected:
            m['prop_frame'] = frame
    return dict(model, meshes=meshes), frames


def add_seat_cages(part, model, lift, prefix):
    """Separate deformable seat cages; chassis-mounted, breakable, no collision spoofing."""
    for group in ('seat_L', 'seat_R'):
        points = [(p[0], -p[2], p[1]+lift) for m in model['meshes']
                  if m.get('acng_group') == group for p in m['positions']]
        if not points:
            continue
        low, high = bounds(points)
        nodes = part.setdefault('nodes', [['id', 'posX', 'posY', 'posZ']])
        nodes.append({'group': prefix+group, 'nodeWeight': 0.3, 'collision': False, 'selfCollision': False})
        ids = []
        for x in (low[0], high[0]):
            for y in (low[1], high[1]):
                for z in (low[2], high[2]):
                    name = prefix+group+str(len(ids));ids.append(name)
                    nodes.append([name, round(x, 6), round(y, 6), round(z, 6)])
        nodes.append({'group': '', 'collision': True, 'selfCollision': True})
        beams = part.setdefault('beams', [['id1:', 'id2:']])
        # Cosmetic nodes are light. Avoid chassis-rate stiffness on their many connections:
        # an over-stiff cage is numerically unstable at BeamNG's physics timestep.
        beams.append({'beamType':'|NORMAL','beamPrecompression':1,'breakGroup':'','deformGroup':'','beamLongBound':1,'beamShortBound':1,'beamSpring': 50000, 'beamDamp': 5, 'beamDeform': 2000, 'beamStrength': 50000})
        for i, a in enumerate(ids):
            for b in ids[i+1:]:
                beams.append([a, b])
        for i in (0, 2, 4, 6):
            for anchor in ('dsh3', 'f7l', 'f7r'):
                beams.append([ids[i], anchor])


def add_prop(part, name, frame, prefix):
    """Damage-attached native prop with an explicit orthonormal reference frame."""
    pivot, axes = frame['pivot'], frame['axes']
    ids = [prefix+name+'_ref', prefix+name+'_x', prefix+name+'_y']
    nodes = part.setdefault('nodes', [['id', 'posX', 'posY', 'posZ']])
    nodes.append({'nodeWeight': 0.15, 'collision': False, 'selfCollision': False,
                  'group': prefix+name+'_mount'})
    positions = [pivot, [pivot[k]+0.08*axes[0][k] for k in range(3)],
                 [pivot[k]+0.08*axes[1][k] for k in range(3)]]
    nodes.extend([[i]+[round(v, 6) for v in p] for i, p in zip(ids, positions)])
    nodes.append({'group': '', 'collision': True, 'selfCollision': True})
    beams = part.setdefault('beams', [['id1:', 'id2:']])
    beams.append({'beamType':'|NORMAL','beamPrecompression':1,'breakGroup':'','deformGroup':'','beamLongBound':1,'beamShortBound':1,'beamSpring': 25000, 'beamDamp': 2, 'beamDeform': 2000, 'beamStrength': 50000})
    for i in ids:
        for anchor in ('dsh1l', 'dsh1r', 'dsh3'):
            beams.append([i, anchor])
    for a, b in ((0, 1), (0, 2), (1, 2)):
        beams.append([ids[a], ids[b]])
    func = 'steering' if name == 'steer' else name.replace('pedal_', '')
    rotation = {'x': 0, 'y': 0, 'z': 1} if name == 'steer' else {'x': -20, 'y': 0, 'z': 0}
    props = part.setdefault('props', [PROP_HEADER])
    props.append([func, prefix+name, *ids, {'x': 0, 'y': 0, 'z': 0}, rotation,
                  {'x': 0, 'y': 0, 'z': 0}, -1000 if name == 'steer' else 0,
                  1000 if name == 'steer' else 1, 0, 1,
                  {'baseTranslation':{'x':0,'y':0,'z':0},
                   'baseRotationGlobal':{'x':70 if name=='steer' else 0,'y':0,'z':0}}])


def spec_parts(stock):
    """Clone local donor parts; original numeric targets, native powertrain retained."""
    engine = copy.deepcopy(stock['etk_engine_i6_3.0'])
    engine['information'] = {'name': 'BMW 1M target 3.0L I6 (experimental)', 'authors': 'ACNG local build'}
    # Net curve calibrated in the local native engine: ~249 kW, ~507 Nm peak.
    # This is a fixed peak-torque approximation, not a timed BMW overboost controller.
    engine['mainEngine']['torque'] = [[rpm, round(torque*(1.0735 if 1000<=rpm<=4500 else 0.9215 if rpm>=5000 else 0.95), 4)] if isinstance(rpm, (int, float))
                                     else [rpm, torque] for rpm, torque in engine['mainEngine']['torque']]
    transmission = copy.deepcopy(stock['etk_transmission_6M_sport'])
    transmission['information'] = {'name': 'BMW 1M 6-speed manual', 'authors': 'ACNG local build'}
    transmission['gearbox']['gearRatios'] = GEAR_RATIOS[:]
    tank=copy.deepcopy(stock['etkc_fueltank'])
    tank['information']={'name':'BMW 1M 53 L fuel tank','authors':'ACNG local build'}
    tank['mainTank']['fuelCapacity']=53
    for row in tank['variables'][1:]:
        if isinstance(row,list) and row[0]=='$fuel':
            row[4],row[6]=47.7,53
    return {'acng_1m_engine': engine, 'acng_1m_transmission': transmission,'acng_1m_fueltank':tank}


def spec_config(pc):
    pc = copy.deepcopy(pc)
    pc['parts'].update(etk_engine='acng_1m_engine', etk_transmission='acng_1m_transmission',
                       etk_finaldrive_R='etk_finaldrive_R_315', etkc_differential_R='etkc_differential_R_LSD',
                       etkc_fueltank='acng_1m_fueltank')
    # Chassis weights remain native: reducing them caused front-subframe self-damage.
    # Accept the measured ~2.5% mass difference instead of breaking damage physics.
    pc.setdefault('vars',{}).update({'$fuel':47.7})
    return pc
