"""Original local BMW 1M fitting/rigging helpers; contains no extracted assets."""
import copy
import math

GEAR_RATIOS = [-3.727, 0, 4.110, 2.315, 1.542, 1.179, 1.000, 0.846]
FINAL_DRIVE = 3.154
# Light cosmetic mounts: about 15% of critical damping, well inside the 2 kHz step limit.
# Keep node weights light; heavier mounts pushed the car past the 3% mass target.
PROP_NODE_KG, PROP_SPRING, PROP_DAMP = 0.15, 40000, 24
STEER_REST_X = 70  # fallback column frame: X rotation of 70 degrees (20 degrees above horizontal)
# Front seat shells, whole bounding box (BeamNG frame, left side; mirrored for the right).
# Wider pieces are sill trims, B-pillar plastics, belts and rear-panel fabric: those are cabin.
SEAT_BOX = ((0.08, 0.66), (-0.25, 0.60), (0.38, 1.05))
BELT_MATERIALS = {'INT_CintureSicurezza'}
# Body-shell triangles in front of the doors, outboard and below the hood line, belong to the
# ETK fender node group (fender nodes: |x| 0.72-0.92, y -1.88..-0.56, z 0.30-0.92).
FENDER_ZONE = {'y_max': -0.58, 'abs_x_min': 0.6, 'z_max': 0.97}
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
    (ax0, ax1), (y0, y1), (z0, z1) = SEAT_BOX
    inside = (ax0 <= min(abs(low[0]), abs(high[0])) and max(abs(low[0]), abs(high[0])) <= ax1
              and low[0]*high[0] > 0 and y0 <= low[1] and high[1] <= y1 and z0 <= low[2] and high[2] <= z1)
    if mesh['material'] not in BELT_MATERIALS and inside and abs(x) > 0.17 and z > 0.46:
        return 'seat_L' if x > 0 else 'seat_R'
    return 'dash' if y < -0.27 and z > 0.57 else 'cabin'


def prepare_model(model, lift):
    meshes = []
    for mesh in model['meshes']:
        path = mesh['path'][:-1]
        if mesh.get('acng_group'):
            meshes.append(mesh)
        elif 'COCKPIT_HR' in path and not any(p.startswith(('DOOR_', 'ARROW_', 'STEER_')) for p in path):
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
        frame = {}
        if name == 'steer':
            frame = steer_node_frame(model, lift)
            if not frame:
                angle = math.radians(20)
                axes = [(1, 0, 0), (0, math.sin(angle), math.cos(angle)),
                        (0, -math.cos(angle), math.sin(angle))]
                frame = {'pivot': pivot, 'axes': axes}
        else:
            pivot[2] = high[2]+0.025
            frame = {'pivot': pivot, 'axes': [(1, 0, 0), (0, 1, 0), (0, 0, 1)]}
        frames[name] = frame
        for m in selected:
            m['prop_frame'] = frame
    return dict(model, meshes=meshes), frames


def steer_node_frame(model, lift):
    """Column frame from the AC STEER_HR node, the axis the AC wheel actually turns about.

    The 1M column points forward and 22 degrees down. The old fixed frame pointed 20 degrees
    up, so steering rotated the wheel about an axis 42 degrees off and it wobbled while turning.
    """
    node = next((n for n in model.get('nodes', []) if n.get('name') == 'STEER_HR'), None)
    if not node:
        return None
    world = node['world']
    axes = []
    for row in world[:3]:
        v = (row[0], -row[2], row[1])
        length = math.sqrt(sum(c*c for c in v))
        if length < 1e-6:
            return None
        axes.append(tuple(c/length for c in v))
    if abs(axes[0][0]) < 0.999:
        return None  # only a column tilted about the car's X axis maps to one rest rotation
    origin = world[3]
    return {'pivot': [origin[0], -origin[2], origin[1]+lift], 'axes': axes,
            'rest_x': round(math.degrees(math.atan2(axes[1][2], axes[1][1])), 3)}


def _subset(mesh, indices, suffix):
    unique = sorted(set(indices)); remap = {v: i for i, v in enumerate(unique)}
    part = dict(mesh, name=mesh['name'] + suffix)
    part['path'] = mesh['path'][:-1] + [part['name']]
    for key in ('positions', 'normals', 'uvs'):
        part[key] = [mesh[key][i] for i in unique]
    part['indices'] = [remap[i] for i in indices]
    return part


def split_fenders(model, lift, is_body):
    """Move front-fender triangles of the body shell to their own fender meshes.

    One body flexbody bound to body, fender, trunk and windshield node groups let each vertex
    follow whichever group was nearest, so crashes stretched and tore the skin between them.
    Vanilla binds each panel to its own group; this does the same for the 1M fenders.
    """
    zone, meshes = FENDER_ZONE, []
    for mesh in model['meshes']:
        if not is_body(mesh):
            meshes.append(mesh); continue
        pts = [(p[0], -p[2], p[1]+lift) for p in mesh['positions']]
        low, high = bounds(pts)
        if not (low[0] < -0.5 and high[0] > 0.5 and high[1]-low[1] > 2.5):
            meshes.append(mesh); continue  # only full-width shell meshes, not struts or cowls
        tris = {'': [], 'fender_L': [], 'fender_R': []}
        ind = mesh['indices']
        for i in range(0, len(ind), 3):
            c = [sum(pts[ind[i+k]][j] for k in range(3))/3 for j in range(3)]
            group = ''
            if c[1] < zone['y_max'] and abs(c[0]) > zone['abs_x_min'] and c[2] < zone['z_max']:
                group = 'fender_L' if c[0] > 0 else 'fender_R'
            tris[group].extend(ind[i:i+3])
        if not tris['fender_L'] and not tris['fender_R']:
            meshes.append(mesh); continue
        for group, inds in tris.items():
            if inds:
                part = _subset(mesh, inds, '_' + (group or 'body'))
                if group:
                    part['acng_group'] = group
                meshes.append(part)
    return dict(model, meshes=meshes)


def add_prop(part, name, frame, prefix):
    """Damage-attached native prop with an explicit orthonormal reference frame."""
    pivot, axes = frame['pivot'], frame['axes']
    ids = [prefix+name+'_ref', prefix+name+'_x', prefix+name+'_y']
    nodes = part.setdefault('nodes', [['id', 'posX', 'posY', 'posZ']])
    nodes.append({'nodeWeight': PROP_NODE_KG, 'collision': False, 'selfCollision': False,
                  'group': prefix+name+'_mount'})
    positions = [pivot, [pivot[k]+0.08*axes[0][k] for k in range(3)],
                 [pivot[k]+0.08*axes[1][k] for k in range(3)]]
    nodes.extend([[i]+[round(v, 6) for v in p] for i, p in zip(ids, positions)])
    nodes.append({'group': '', 'collision': True, 'selfCollision': True})
    beams = part.setdefault('beams', [['id1:', 'id2:']])
    beams.append({'beamType':'|NORMAL','beamPrecompression':1,'breakGroup':'','deformGroup':'','beamLongBound':1,'beamShortBound':1,'beamSpring': PROP_SPRING, 'beamDamp': PROP_DAMP, 'beamDeform': 2000, 'beamStrength': 50000})
    for i in ids:
        for anchor in ('dsh1l', 'dsh1r', 'dsh3'):
            beams.append([i, anchor])
    for a, b in ((0, 1), (0, 2), (1, 2)):
        beams.append([ids[a], ids[b]])
    func = frame.get('func', 'steering' if name == 'steer' else name.replace('pedal_', ''))
    rotation = {'x': 0, 'y': 0, 'z': frame['rate']} if 'rate' in frame else {'x': 0, 'y': 0, 'z': 1} if name == 'steer' else {'x': -20, 'y': 0, 'z': 0}
    props = part.setdefault('props', [PROP_HEADER])
    props.append([func, prefix+name, *ids, {'x': 0, 'y': 0, 'z': 0}, rotation,
                  {'x': 0, 'y': 0, 'z': 0}, frame.get('min', -1000 if name == 'steer' else 0),
                  frame.get('max', 1000 if name == 'steer' else 1), frame.get('offset', 0), 1,
                  {'baseTranslation':{'x':0,'y':0,'z':0},
                   'baseRotationGlobal':{'x':prop_rest_x(name, frame),'y':0,'z':0}}])


def prop_rest_x(name, frame):
    """BeamNG baseRotationGlobal X turns opposite to the right-hand rule used for the frames.

    Vanilla columns that rise toward the driver use negative X (md_series -21, sunburst2
    -20.8/-47.45). The old positive value left the 1M wheel and dials about 140 degrees off.
    """
    return -frame.get('rest_x', STEER_REST_X if name == 'steer' else 0)


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
