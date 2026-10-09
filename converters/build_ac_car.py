"""Build a personal, local BeamNG car from the user's own Assetto Corsa car on the stock ETK K-Series.

Original code. BeamNG retains the chassis, suspension and damage simulation. The ETK K-Series
is fitted to the AC car's wheelbase/roof; separate interior flexbodies and native control props
are added. A local specification config calibrates the native powertrain, gearing and fuel tank;
a separate donor config retains ETK powertrain values. Chassis node weights stay native.

Output goes OUTSIDE this repository and is never committed or distributed: it contains the
user's AC car meshes/textures and copies of the user's own BeamNG etkc mesh files.

Usage:
  python converters/build_ac_car.py --ac-car <assettocorsa>/content/cars/bmw_1m \
      --beamng <BeamNG.drive install> --out <folder outside the repo> [--skin valencia_orange]
"""
import argparse
import copy
import car_sounds
import car_upgrades
import car_details
import io
import json
import re
import shutil
import sys
import zipfile
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import export_kn5  # noqa: E402
import jbeam_io  # noqa: E402
import kn5_model  # noqa: E402

VEHICLE = 'acng_bmw1m'
CONFIG = 'acng_bmw1m_M'
BASE_CONFIG = 'kc6_360_M'

# Node transform: stretch length to the 1M wheelbase (ETK 2.588 m -> 1M 2.660 m, wheel centres
# re-centred on the AC body) and raise the roof (ETK roof ~1.35 m -> 1M ~1.42 m). Width unchanged.
SY, TY = 1.0322, 0.0107
Z_KNEE, Z_SCALE = 0.9, 1.15
# The ETK front overhang is ~0.17 m longer than the 1M's (bumper nodes reach -2.28 m, the AC
# bumper skin -2.11 m), so bumper, headlight and hood nodes sat ahead of the panels they carry and
# crumpling stretched those panels into long shards. Nodes ahead of the front tyres are pulled in
# to the 1M overhang; the suspension, subframe and engine nodes all lie behind the knee.
Y_KNEE_F, Y_SCALE_F = -1.6, 0.75
MESH_LIFT = 0.016  # AC ground plane vs ETK node frame, from the wheel-centre fit

# Visible ETK meshes are removed; these mechanical ones stay (seen through wheel wells and in crashes).
# Not the ETK wheel-well tubs: their edge poked out of the 1M arch as a black lip; AC has its own liners.
KEEP_PREFIXES = ('etkc_lowerarm', 'etkc_tierod', 'etkc_hub', 'etkc_upperarm', 'etkc_subframe', 'etkc_diff',
                 'etkc_halfshaft', 'etkc_spring', 'etkc_shock', 'etkc_swaybar', 'etkc_strut', 'etkc_steeringbox',
                 'etkc_underbody', 'etkc_radsupport', 'etkc_heatshield',
                 'etkc_fueltank', 'etkc_radiator', 'etkc_driveshaft', 'etkc_transfercase', 'etkc_exhaust_',
                 'etkc_muffler', 'etkc_catalytic', 'etkc_intercooler')

# AC mesh group -> (ETK part that owns the flexbody, ETK node groups it deforms with).
# One node group per panel, as vanilla does: spanning several let a vertex follow whichever
# group was nearest, so crashes stretched and tore the skin between panels.
FLEXBODIES = {
    'body': ('etkc_body', ['etkc_body']),
    'fender_L': ('etkc_fender_L', ['etkc_fender_L']),
    'fender_R': ('etkc_fender_R', ['etkc_fender_R']),
    **{side: ('etkc_body', [group]) for sides in car_upgrades.LAMP_SIDES.values()
       for side, group in sides.items()},
    'door_L': ('etkc_door_L', ['etkc_door_L']),
    'door_R': ('etkc_door_R', ['etkc_door_R']),
    'hood': ('etkc_hood', ['etkc_hood']),
    'bumper_F': ('etkc_bumper_F', ['etkc_bumper_F']),
    'bumper_R': ('etkc_bumper_R', ['etkc_bumper_R']),
    'trunk': ('etkc_trunk', ['etkc_trunk']),
    'dash': ('etkc_dash', ['etkc_dash']),
    'cabin': ('etkc_dash', ['etkc_body']),
    'seat_L': ('etkc_seat_FL', ['etkc_floor', 'etkc_seat_FL']),  # native seat nodes, as vanilla
    'seat_R': ('etkc_seat_FR', ['etkc_floor', 'etkc_seat_FR']),
    'shifter': ('etkc_shifter_M', ['etkc_shifterknob_M']),
    'shifter_boot': ('etkc_shifter_M', ['etkc_shifterboot_M', 'etkc_shifterbase_M']),
}


def tf_y(y):
    y = SY*y+TY
    return Y_KNEE_F + Y_SCALE_F * (y - Y_KNEE_F) if y < Y_KNEE_F else y


def tf_z(z):
    return Z_KNEE + Z_SCALE * (z - Z_KNEE) if z > Z_KNEE else z


def strip_visible(mesh):
    if not isinstance(mesh, str):
        return False
    if mesh.startswith('$='):
        return 'etkc_' in mesh
    if mesh == 'etkc_radsupport':
        return True
    if mesh == 'licenseplate':
        return True
    return mesh.startswith('etkc_') and not mesh.startswith(KEEP_PREFIXES)


def _table(rows, transform):
    """Apply transform(row, header) to each data row of a JBeam table, keeping modifier dicts."""
    if not rows or not isinstance(rows[0], list):
        return rows
    header, out = rows[0], [rows[0]]
    for row in rows[1:]:
        if isinstance(row, list):
            row = transform(row, header)
            if row is None:
                continue
        out.append(row)
    return out


def _move_point(row, header, kx, ky, kz):
    row = list(row)
    iy, iz = header.index(ky), header.index(kz)
    if isinstance(row[iy], (int, float)):
        row[iy] = round(tf_y(row[iy]), 5)
    if isinstance(row[iz], (int, float)):
        row[iz] = round(tf_z(row[iz]), 5)
    return row


def transform_part(name, part, local_slot_types, common_centroids):
    part = dict(part)
    report = {'stripped': []}
    if 'nodes' in part:
        part['nodes'] = _table(part['nodes'], lambda r, h: _move_point(r, h, 'posX', 'posY', 'posZ'))
    if 'camerasInternal' in part:
        part['camerasInternal'] = _table(part['camerasInternal'], lambda r, h: _move_point(r, h, 'x', 'y', 'z'))

    def flex(row, header):
        mesh = row[header.index('mesh')]
        if strip_visible(mesh):
            report['stripped'].append(mesh)
            return None
        return row

    def prop(row, header):
        mesh = row[header.index('mesh')]
        if strip_visible(mesh):
            report['stripped'].append(mesh)
            return None
        return row

    if 'flexbodies' in part:
        part['flexbodies'] = _table(part['flexbodies'], flex)
    if 'props' in part:
        part['props'] = _table(part['props'], prop)
    part.pop('mirrors', None)  # reflection planes belonged to the removed ETK mirror meshes

    for key in ('slots2', 'slots'):
        if key not in part:
            continue

        def slot(row, header):
            row = list(row)
            opts = row[-1] if isinstance(row[-1], dict) else None
            if not opts or 'nodeOffset' not in opts:
                return row
            off = dict(opts['nodeOffset'])
            allow = row[1] if key == 'slots2' else [row[0]]
            allow = allow if isinstance(allow, list) else [allow]
            default = row[3] if key == 'slots2' else row[1]
            if any(t in local_slot_types for t in allow):
                # Child nodes are etkc nodes already transformed; only the offset length scales.
                if isinstance(off.get('y'), (int, float)):
                    off['y'] = round(SY * off['y'], 5)
            else:
                # Common child (wheels, engine): move its centre as if it were an etkc point.
                cy, cz = common_centroids.get(default, (0.0, 0.0))
                if isinstance(off.get('y'), (int, float)):
                    off['y'] = round(tf_y(cy + off['y']) - cy, 5)
                if isinstance(off.get('z'), (int, float)) and cz:
                    off['z'] = round(tf_z(cz + off['z']) - cz, 5)
            row[-1] = dict(opts, nodeOffset=off)
            return row

        part[key] = _table(part[key], slot)
    return part, report


def common_centroids(common_zip, names):
    """Mean (y, z) of the nodes of named common parts, used to place offset common children."""
    found = {}
    with zipfile.ZipFile(common_zip) as z:
        for n in z.namelist():
            if not n.endswith('.jbeam') or '/etk' not in n.lower():
                continue
            try:
                data = jbeam_io.loads(z.read(n).decode('utf-8', 'replace'))
            except ValueError:
                continue
            for pname in names & data.keys():
                rows = [r for r in data[pname].get('nodes', [])[1:] if isinstance(r, list)]
                pts = [(r[2], r[3]) for r in rows if isinstance(r[2], (int, float)) and isinstance(r[3], (int, float))]
                if pts:
                    found[pname] = (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))
    return found


def flexbody_clouds(files, pc):
    """Transformed node positions of each FLEXBODIES target, from the parts the config installs."""
    installed = {v for v in pc['parts'].values() if v} | {'etkc'}
    groups = {}
    for data in files.values():
        for pname, part in data.items():
            if pname not in installed or not isinstance(part, dict):
                continue
            current = []
            for row in part.get('nodes', [])[1:]:
                if isinstance(row, dict) and 'group' in row:
                    g = row['group']
                    current = g if isinstance(g, list) else [g] if g else []
                elif isinstance(row, list) and len(row) > 3 and all(isinstance(v, (int, float)) for v in row[1:4]):
                    for g in current:
                        groups.setdefault(g, []).append(tuple(row[1:4]))
    return {target: [p for g in node_groups for p in groups.get(g, [])]
            for target, (_, node_groups) in FLEXBODIES.items()}


# BeamNG's own paint presets (vanilla info.json): solid paints are glossy without a separate
# clear coat; metallic paints have a rough flake base under a smooth clear coat. AC's 1M skins
# carry no paint type, so the solid ones are listed by name.
SOLID_SKINS = {'white', 'crimson_red', 'red'}
SOLID_PAINT = {'metallic': 0, 'roughness': 0.07, 'clearcoat': 0, 'clearcoatRoughness': 0}
METALLIC_PAINT = {'metallic': 0.8, 'roughness': 0.65, 'clearcoat': 1, 'clearcoatRoughness': 0.05}


def paint_label(skin):
    """Paint name shown in the BeamNG colour picker for an AC skin folder ('0_orange' -> 'Orange')."""
    return re.sub(r'^\d+_', '', skin).replace('_', ' ').title()


def ac_paints(ac_car):
    """BeamNG paint presets from the AC skins' paint colour (metal_detail.dds mean colour)."""
    from PIL import Image, ImageStat
    paints = {}
    for skin in sorted((ac_car / 'skins').iterdir()):
        tex = skin / 'metal_detail.dds'
        if not tex.is_file():
            continue
        with Image.open(tex) as im:
            r, g, b = ImageStat.Stat(im.convert('RGB')).mean
        finish = SOLID_PAINT if skin.name in SOLID_SKINS else METALLIC_PAINT
        paints.setdefault(paint_label(skin.name),
                          {'baseColor': [round(r / 255, 4), round(g / 255, 4), round(b / 255, 4), 1.2], **finish})
    return paints


def build(ac_car, beamng, out_root, skin):
    ac_car, beamng = Path(ac_car), Path(beamng)
    out_root = export_kn5.guard_output(out_root)
    vdir = out_root / 'vehicles' / VEHICLE
    if vdir.exists():
        if any(vdir.iterdir()) and not (vdir / f'{VEHICLE}.dae').is_file():
            raise SystemExit(f'{vdir} exists but is not a previous build of this tool; refusing to replace it.')
        shutil.rmtree(vdir)  # our own previous build output only
    vdir.mkdir(parents=True)
    etkc_zip = beamng / 'content' / 'vehicles' / 'etkc.zip'
    common_zip = beamng / 'content' / 'vehicles' / 'common.zip'

    model = kn5_model.read((ac_car / (ac_car.name + '.kn5')).read_bytes())
    model,gauge_frames,mirror_centers=car_details.prepare(model,MESH_LIFT)
    model,prop_frames=car_upgrades.prepare_model(model,MESH_LIFT)
    prop_frames.update(gauge_frames)
    report = {'prop_frames': prop_frames}

    with zipfile.ZipFile(etkc_zip) as z:
        files = {}
        for n in z.namelist():
            if n.startswith('vehicles/etkc/') and n.endswith('.jbeam'):
                files[n[len('vehicles/etkc/'):]] = jbeam_io.loads(z.read(n).decode('utf-8', 'replace'))
        local_types = {p.get('slotType') for f in files.values() for p in f.values()}
        slot_defaults = set()
        for f in files.values():
            for p in f.values():
                for row in p.get('slots2', [])[1:]:
                    if isinstance(row, list) and isinstance(row[-1], dict) and 'nodeOffset' in row[-1]:
                        slot_defaults.add(row[3])
        centroids = common_centroids(common_zip, slot_defaults)
        report['common_centroids'] = centroids
        stripped = []
        for fname, data in files.items():
            for pname in list(data):
                data[pname], r = transform_part(pname, data[pname], local_types, centroids)
                stripped += r['stripped']
                if pname == 'etkc':
                    data[pname]['information'] = {'authors': 'local AC conversion (personal use)',
                                                  'name': 'BMW 1M (local)'}
        pc = json.loads(z.read(f'vehicles/etkc/{BASE_CONFIG}.pc'))
        clouds = flexbody_clouds(files, pc)
        materials={m['name']:m for m in model['materials']}
        model=car_upgrades.split_fenders(model,MESH_LIFT,lambda m:export_kn5.route(m,materials)=='body')
        model=car_upgrades.split_lamps(model,MESH_LIFT,lambda m:export_kn5.route(m,materials))
        model,report['rerouted_lamp_triangles']=car_upgrades.reroute_lamps(
            model,MESH_LIFT,lambda m:export_kn5.route(m,materials),clouds)
        model,report['rerouted_fender_triangles']=car_upgrades.reroute_fenders(
            model,MESH_LIFT,lambda m:export_kn5.route(m,materials),clouds)
        report['mesh'] = export_kn5.export(model, vdir, VEHICLE, VEHICLE + '_', MESH_LIFT)
        groups = report['mesh']['groups']
        # Native light switching: electrics swap each AC lamp to its emissive copy.
        next(d['etkc'] for d in files.values() if 'etkc' in d).setdefault('glowMap', {}).update(report['mesh']['glow'])
        # Bind each exported AC mesh (and any lettered overflow mesh) to its ETK damage groups.
        added = []
        for gname in groups:
            target = gname[len(VEHICLE) + 1:]
            base = re.sub(r'_[a-h]$', '', target) if target not in FLEXBODIES else target
            if base in prop_frames:
                continue
            if base.startswith(('mirror_', 'rim_')):
                continue  # native mirror/rim parts own these detail meshes
            owner, node_groups = FLEXBODIES[base]
            for data in files.values():
                if owner in data:
                    flex = data[owner].setdefault('flexbodies', [['mesh', '[group]:', 'nonFlexMaterials']])
                    flex.append([gname, node_groups])
                    added.append((gname, owner))
        for data in files.values():
            if 'etkc_dash' in data:
                for name,frame in prop_frames.items():
                    car_upgrades.add_prop(data['etkc_dash'], name,frame,VEHICLE+'_')
        car_details.add_mirrors(files,mirror_centers,VEHICLE+'_')
        report['mirror_centers']=mirror_centers
        report['stripped_meshes'] = sorted(set(stripped))
        report['added_flexbodies'] = added
        for fname, data in files.items():
            (vdir / fname).parent.mkdir(parents=True,exist_ok=True)
            (vdir / fname).write_text(jbeam_io.dumps(data), encoding='ascii')
        # The kept mechanical flexbodies need etkc's own meshes; copy them from the user's install.
        for n in ('etkc.cdae', 'etkc_extraparts.cdae', 'etkc_transfercase.cdae'):
            (vdir / n).write_bytes(z.read('vehicles/etkc/' + n))
        (vdir / 'etkc_base.materials.json').write_bytes(z.read('vehicles/etkc/main.materials.json'))

    pc['model'] = VEHICLE
    for slot in ('etkc_licenseplate_R', 'etkc_lettering_trunk', 'etkc_lettering_kc6', 'etkc_logo_F'):
        pc['parts'][slot] = ''
    pc=car_details.wheel_config(pc)
    old_pc=copy.deepcopy(pc)
    (vdir / 'acng_etk_baseline.pc').write_text(json.dumps(old_pc,indent=2),encoding='ascii')
    stock={}
    with zipfile.ZipFile(common_zip) as common:
        for name in common.namelist():
            if name.endswith('.jbeam') and '/etk' in name.lower():
                try: stock.update(jbeam_io.loads(common.read(name).decode('utf-8','replace')))
                except ValueError: pass
    stock['etkc_fueltank']=next(data['etkc_fueltank'] for data in files.values() if 'etkc_fueltank' in data)
    parts=car_upgrades.spec_parts(stock)
    bank = ac_car / 'sfx' / (ac_car.name + '.bank')
    if bank.is_file():  # the user's own AC recordings; written to the build output only
        car_sounds.apply(parts['acng_1m_engine'], car_sounds.write(bank, vdir, VEHICLE))
    parts.update(car_details.wheel_parts(stock,VEHICLE+'_'))
    (vdir / 'acng_1m_specs.jbeam').write_text(jbeam_io.dumps(parts),encoding='ascii')
    pc=car_upgrades.spec_config(pc)
    (vdir / f'{CONFIG}.pc').write_text(json.dumps(pc, indent=2), encoding='ascii')
    (vdir / 'info_acng_etk_baseline.json').write_text(json.dumps({'Configuration':'ETK donor baseline','Config Type':'Custom','Drivetrain':'RWD','Transmission':'Manual'}),encoding='ascii')

    paints = ac_paints(ac_car)
    default_paint = paint_label(skin)
    info = {'Author': 'Local conversion of the user\'s own Assetto Corsa car (personal use only)',
            'Brand': 'BMW', 'Body Style': 'Coupe', 'Country': 'Germany', 'Name': 'BMW 1M (local)',
            'Type': 'Car', 'Years': {'min': 2011, 'max': 2012}, 'default_pc': CONFIG,
            'defaultPaintName1': default_paint if default_paint in paints else next(iter(paints), ''),
            'paints': paints}
    (vdir / 'info.json').write_text(json.dumps(info, indent=2), encoding='ascii')
    (vdir / f'info_{CONFIG}.json').write_text(json.dumps(
        {'Configuration': '1M specifications target (experimental)', 'Config Type': 'Custom', 'Drivetrain': 'RWD',
         'Transmission': 'Manual', 'defaultPaintName1': info['defaultPaintName1']}, indent=2), encoding='ascii')
    preview = ac_car / 'skins' / skin / 'preview.jpg'
    if preview.is_file():
        shutil.copyfile(preview, vdir / 'default.jpg')
        shutil.copyfile(preview, vdir / f'{CONFIG}.jpg')

    zpath = out_root / f'{VEHICLE}.zip'
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED) as zout:
        for f in sorted(vdir.rglob('*')):
            if f.is_file():
                data = f.read_bytes()
                # BeamNG misreads a deflated entry whose compressed size equals its size (C001:
                # "stream doesn't contain a PNG"), so incompressible files are stored instead.
                deflated = zlib.compressobj(9, zlib.DEFLATED, -15)
                packed = len(deflated.compress(data) + deflated.flush())
                kind = zipfile.ZIP_DEFLATED if packed < len(data) * 0.98 else zipfile.ZIP_STORED
                zout.writestr(zipfile.ZipInfo.from_file(f, f.relative_to(out_root).as_posix()), data, kind)
    zpath.write_bytes(buf.getvalue())
    report['zip'] = str(zpath)
    report['zip_bytes'] = zpath.stat().st_size
    (out_root / 'build_report.json').write_text(json.dumps(report, indent=1), encoding='ascii')
    return report


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--ac-car', required=True)
    ap.add_argument('--beamng', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--skin', default='valencia_orange')
    a = ap.parse_args()
    r = build(a.ac_car, a.beamng, a.out, a.skin)
    print(json.dumps({'zip': r['zip'], 'zip_bytes': r['zip_bytes'], 'flexbodies': len(r['added_flexbodies']),
                      'stripped': len(r['stripped_meshes']), 'centroids': r['common_centroids']}, indent=1))


if __name__ == '__main__':
    main()
