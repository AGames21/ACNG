"""Original native instruments, mirrors and rim adapters for the local 1M build.

Geometry is read from an owned installation at build time, never stored here.
"""
import copy
import math

# Original display calibration from visible markings; BeamNG inputs use SI units.
GAUGES = {
    'ARROW_RPM': ('gauge_rpm', 'rpm', 0, 8000, 0, 256 / 8000),
    'ARROW_SPEED': ('gauge_speed', 'wheelspeed', 0, 300 / 3.6, 0, 256 / (300 / 3.6)),
    'ARROW_FUEL': ('gauge_fuel', 'fuel', 0, 1, -0.5, -100),
    # The small dial below the tach is oil temperature in Fahrenheit (160/250/340).
    'ARROW_FUEL1': ('gauge_oil', 'oiltemp', (160-32)/1.8, (340-32)/1.8,
                    -(250-32)/1.8, -1),
}
WHEELS = {'LF': 'FL', 'RF': 'FR', 'LR': 'RL', 'RR': 'RR'}
IDENTITY = [(1, 0, 0), (0, 1, 0), (0, 0, 1)]


def point(p, lift=0):
    return (p[0], -p[2], p[1]+lift)


def prepare(model, lift):
    """Mark detail meshes before generic routing and interior splitting."""
    nodes = {tuple(n['path']): n for n in model.get('nodes', [])}
    frames, mirrors, meshes = {}, {}, []
    for original in model['meshes']:
        mesh = dict(original)
        parents = mesh['path'][:-1]
        for index, parent in enumerate(parents):
            if parent in GAUGES:
                name, func, minimum, maximum, offset, rate = GAUGES[parent]
                transform = nodes[tuple(parents[:index+1])]['world']
                normal = point(transform[2][:3])
                tilt = math.atan2(-normal[1], normal[2])
                axes = [(1, 0, 0), (0, math.cos(tilt), math.sin(tilt)),
                        (0, -math.sin(tilt), math.cos(tilt))]
                frame = {'pivot': point(transform[3][:3], lift), 'axes': axes,
                         'rest_x': math.degrees(tilt), 'func': func, 'min': minimum,
                         'max': maximum, 'offset': offset, 'rate': rate}
                frames[name] = frame
                mesh.update(acng_group=name, prop_frame=frame)
                break
        if mesh['material'] == 'MIRROR' and mesh.get('active') and mesh.get('visible'):
            name = 'mirror_L' if 'DOOR_L' in parents else 'mirror_R' if 'DOOR_R' in parents else 'mirror_C'
            mesh['acng_group'] = name
            pts = [point(p, lift) for p in mesh['positions']]
            mirrors[name] = [(min(p[k] for p in pts)+max(p[k] for p in pts))/2 for k in range(3)]
            # AC uses atlas subsets and negative V. A native mirror render target
            # needs the complete face UV range, not a repeated atlas fragment.
            low = [min(uv[k] for uv in mesh['uvs']) for k in (0, 1)]
            span = [max(uv[k] for uv in mesh['uvs'])-low[k] for k in (0, 1)]
            if min(span) <= 1e-8:
                raise ValueError('Mirror face has degenerate UVs: '+name)
            mesh['uvs'] = [tuple((uv[k]-low[k])/span[k] for k in (0, 1)) for uv in mesh['uvs']]
        for ac, beam in WHEELS.items():
            if 'RIM_'+ac in parents and 'WHEEL_'+ac in parents:
                # AC tires, blur and brake meshes stay excluded. Native pressure
                # wheels retain tire, brake/suspension and damage behavior.
                index = parents.index('WHEEL_'+ac)
                pivot = point(nodes[tuple(parents[:index+1])]['world'][3][:3], lift)
                mesh.update(acng_group='rim_'+beam,
                            prop_frame={'pivot': pivot, 'axes': IDENTITY})
        meshes.append(mesh)
    return dict(model, meshes=meshes), frames, mirrors


def add_mirrors(files, centers, prefix):
    """Attach native mirror cameras and flexbodies to native damage groups."""
    parts = {name: p for data in files.values() for name, p in data.items()}
    positions = {row[0]: row[1:4] for p in parts.values()
                 for row in p.get('nodes', [])[1:] if isinstance(row, list)}
    specs = {
        'mirror_L': ('etkc_mirror_L', 'mi4l', 'mi3l', 'mi2l', -5, ['etkc_mirror_L']),
        'mirror_R': ('etkc_mirror_R', 'mi4r', 'mi3r', 'mi2r', 20, ['etkc_mirror_R']),
        'mirror_C': ('etkc_dash', 'rf1', 'rf1r', 'rf2', 20, ['etkc_body', 'etkc_windshield']),
    }
    for name, center in centers.items():
        owner, ref, x, y, yaw, groups = specs[name]
        part = parts[owner]
        offset = {axis: round(center[k]-positions[ref][k], 6) for k, axis in enumerate('xyz')}
        part.setdefault('flexbodies', [['mesh', '[group]:', 'nonFlexMaterials']]).append([prefix+name, groups])
        part.setdefault('mirrors', [['mesh', 'idRef:', 'id1:', 'id2:']]).append(
            [prefix+name, ref, x, y, {'refBaseTranslation': offset,
             'baseRotationGlobal': {'x': 0, 'y': 0, 'z': yaw},
             'label': {'mirror_L':'Left mirror', 'mirror_R':'Right mirror', 'mirror_C':'Interior mirror'}[name]}])


def wheel_parts(stock, prefix):
    """Clone selected rims, changing visual bindings only. Keep native physics."""
    result = {}
    for axle, donor in (('F', 'etk_wheel_08a_19x9_F'), ('R', 'etk_wheel_08a_19x10_R')):
        part = copy.deepcopy(stock[donor])
        part['information'] = {'name': 'BMW 1M 19-inch rims ('+axle+')', 'authors': 'ACNG local build'}
        for row in part['flexbodies'][1:]:
            if not isinstance(row, list):
                continue
            side = next(g[-2:] for g in row[1] if g.startswith('wheel_'))
            row[0] = prefix+'rim_'+side
            row[-1]['rot'] = {'x': 0, 'y': 0, 'z': 0}
            row[-1]['scale'] = {'x': 1, 'y': 1, 'z': 1}
        result['acng_1m_wheel_'+axle] = part
    return result


def wheel_config(pc):
    pc = copy.deepcopy(pc)
    pc['parts'].update(wheel_F_5='acng_1m_wheel_F', wheel_R_5='acng_1m_wheel_R')
    # Native hub offsets plus bindings +/-0.51 front, +/-0.50 rear match AC pivots.
    pc.setdefault('vars', {}).update({'$trackwidth_F': 0.2438, '$trackwidth_R': 0.254})
    return pc
