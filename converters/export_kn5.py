"""Guarded KN5 -> BeamNG mesh exporter for a personal, local car conversion.

Original code. Reads the user's own Assetto Corsa car with kn5_model.read() and writes, to a
folder OUTSIDE this repository only:
  - one Collada file with one mesh per damage group (body, doors, hood, bumpers, ...)
  - the KN5's embedded textures: .dds when BeamNG can read the format, otherwise PNG,
    plus derived paint/opacity PNGs
  - a BeamNG 1.5 materials file
Nothing it writes may be committed or distributed (see docs/AC-CAR-CONVERSION.md).

Frames: AC is X left, Y up, Z forward. BeamNG is X left, Y backward, Z up.
BeamNG (x, y, z) = (AC x, -AC z, AC y + lift). That is a proper rotation, so triangle
winding is kept unless a mesh's geometric normals disagree with its stored normals.
"""
import io
import struct
import json
import os
from pathlib import Path
from xml.sax.saxutils import escape

REPO_ROOT = Path(__file__).resolve().parents[1]
MAX_VERTS = 60000  # stay under 16-bit index limits per mesh

# Mesh routing: first matching rule wins. Each rule is (target, test(mesh) -> bool).
SKIP = 'skip'


def _path(mesh):
    return [p for p in mesh['path']]


def _under(mesh, *names):
    return any(any(part == n or part.startswith(n + '/') for n in names) for part in _path(mesh)[:-1])


def _center_y(mesh):
    # AC forward (+Z) is BeamNG -Y; positive AC z = front of the car.
    zs = [p[2] for p in mesh['positions']]
    return sum(zs) / max(1, len(zs))


HEADLIGHT_MATERIALS = {'FANALI_Anteriori', 'FANALI_Anteriori_Trasp', 'Dettaglio_Faro'}
TAILLIGHT_MATERIALS = {'Fanali_POSTERIORI_OS', 'Fanali_POSTERIORI_TS', 'FARI_Poseriori_EXTRA1',
                       'FARI_Poseriori_EXTRA2'}


def route(mesh, materials):
    """Return the target mesh group for one KN5 mesh, or SKIP."""
    name = mesh['name']
    parents = _path(mesh)[:-1]
    shader = materials[mesh['material']]['shader']
    if not mesh['active'] or not mesh['visible']:
        return SKIP
    # Broken-glass overlays, AC-only LOD/cockpit duplicates, needles and the worn seat belt.
    if shader == 'ksBrokenGlass' or any(p.startswith('DAMAGE_GLASS') for p in parents):
        return SKIP
    if any(p.startswith(('WHEEL_', 'SUSP_', 'DISC_', 'COCKPIT_LR', 'CINTURE_ON', 'ARROW_')) for p in parents):
        return SKIP
    if mesh['material'] == 'INT_VETRO_INTERNO':
        return SKIP
    if 'DOOR_L1' in parents or 'DOOR_L' in parents:
        return 'door_L'
    if 'DOOR_R1' in parents or 'DOOR_R' in parents:
        return 'door_R'
    if 'MOTORHOOD' in parents:
        return 'hood'
    if 'FRONT_BUMPER' in parents:
        return 'bumper_F'
    if 'REAR_BUMPER' in parents:
        return 'bumper_R'
    if 'STEER_HR' in parents:
        return 'steer'
    if 'COCKPIT_HR' in parents or 'CINTURE_OFF' in parents:
        return 'interior'
    if name in ('Plate_LODA', 'brake_light_2'):
        return 'trunk'
    front = _center_y(mesh) > 0
    if mesh['material'] in HEADLIGHT_MATERIALS or name.startswith('front_light'):
        return 'lights_F'
    if mesh['material'] in TAILLIGHT_MATERIALS or name.startswith(('rear_light', 'brake_light', 'retro_light')):
        return 'lights_R'
    if mesh['material'] == 'VETRI_Fanali':
        return 'lights_F' if front else 'lights_R'
    return 'body'


def to_beamng(p, lift):
    return (p[0], -p[2], p[1] + lift)


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def convert_mesh(mesh, lift):
    """Return (positions, normals, uvs, triangles, flipped) in BeamNG frame."""
    pos = [to_beamng(p, lift) for p in mesh['positions']]
    nrm = [to_beamng(n, 0.0) for n in mesh['normals']]
    uvs = [(u, 1.0 - v) for u, v in mesh['uvs']]
    tris = [tuple(mesh['indices'][i:i + 3]) for i in range(0, len(mesh['indices']), 3)]
    agree = disagree = 0
    for a, b, c in tris:
        g = _cross(_sub(pos[b], pos[a]), _sub(pos[c], pos[a]))
        n = tuple(nrm[a][k] + nrm[b][k] + nrm[c][k] for k in range(3))
        d = _dot(g, n)
        if d > 0:
            agree += 1
        elif d < 0:
            disagree += 1
    flipped = disagree > agree
    if flipped:
        tris = [(a, c, b) for a, b, c in tris]
    return pos, nrm, uvs, tris, flipped


class Group:
    def __init__(self, name):
        self.name = name
        self.pos, self.nrm, self.uv = [], [], []
        self.tris = {}  # material -> list of index triples

    def add(self, material, pos, nrm, uvs, tris):
        base = len(self.pos)
        self.pos += pos
        self.nrm += nrm
        self.uv += uvs
        self.tris.setdefault(material, []).extend((a + base, b + base, c + base) for a, b, c in tris)


def _floats(values):
    return ' '.join(f'{v:.6g}' for v in values)


def write_collada(groups, path, material_names):
    out = ['<?xml version="1.0" encoding="utf-8"?>',
           '<COLLADA xmlns="http://www.collada.org/2005/11/COLLADASchema" version="1.4.1">',
           '<asset><unit name="meter" meter="1"/><up_axis>Z_UP</up_axis></asset>',
           '<library_effects>']
    used = sorted({m for g in groups for m in g.tris})
    for m in used:
        mid = escape(material_names[m])
        out.append(f'<effect id="{mid}-fx"><profile_COMMON><technique sid="common"><lambert>'
                   '<diffuse><color>0.8 0.8 0.8 1</color></diffuse></lambert></technique></profile_COMMON></effect>')
    out.append('</library_effects><library_materials>')
    for m in used:
        mid = escape(material_names[m])
        out.append(f'<material id="{mid}" name="{mid}"><instance_effect url="#{mid}-fx"/></material>')
    out.append('</library_materials><library_geometries>')
    for g in groups:
        n = g.name
        v = len(g.pos)
        out.append(f'<geometry id="{n}-mesh" name="{n}"><mesh>')
        for suffix, data, params in (('pos', g.pos, 'XYZ'), ('nrm', g.nrm, 'XYZ'), ('uv', g.uv, 'ST')):
            flat = [c for item in data for c in item]
            out.append(f'<source id="{n}-{suffix}"><float_array id="{n}-{suffix}-array" count="{len(flat)}">'
                       f'{_floats(flat)}</float_array><technique_common>'
                       f'<accessor source="#{n}-{suffix}-array" count="{v}" stride="{len(params)}">'
                       + ''.join(f'<param name="{p}" type="float"/>' for p in params)
                       + '</accessor></technique_common></source>')
        out.append(f'<vertices id="{n}-vtx"><input semantic="POSITION" source="#{n}-pos"/></vertices>')
        for m, tris in sorted(g.tris.items()):
            mid = escape(material_names[m])
            idx = ' '.join(str(i) for t in tris for i in t)
            out.append(f'<triangles material="{mid}" count="{len(tris)}">'
                       f'<input semantic="VERTEX" source="#{n}-vtx" offset="0"/>'
                       f'<input semantic="NORMAL" source="#{n}-nrm" offset="0"/>'
                       f'<input semantic="TEXCOORD" source="#{n}-uv" offset="0" set="0"/>'
                       f'<p>{idx}</p></triangles>')
        out.append('</mesh></geometry>')
    out.append('</library_geometries><library_visual_scenes><visual_scene id="Scene" name="Scene">')
    for g in groups:
        n = g.name
        binds = ''.join(f'<instance_material symbol="{escape(material_names[m])}" target="#{escape(material_names[m])}"/>'
                        for m in sorted(g.tris))
        out.append(f'<node id="{n}" name="{n}" type="NODE"><instance_geometry url="#{n}-mesh" name="{n}">'
                   f'<bind_material><technique_common>{binds}</technique_common></bind_material>'
                   '</instance_geometry></node>')
    out.append('</visual_scene></library_visual_scenes><scene><instance_visual_scene url="#Scene"/></scene></COLLADA>')
    path.write_text('\n'.join(out), encoding='ascii')


METALLIC = {'INT_Cromato', 'MIRROR', 'Chassis_METAL', 'LOGHI_RIM'}


def _texture_file(name):
    return 'textures/' + name.lower().replace(' ', '_')


# BeamNG 0.39 reads block-compressed DDS only. It rejects AC's uncompressed DDS (32-bit ARGB,
# 24-bit, 16-bit, luminance-alpha: "only RGB formats are supported"); those become PNG.
_NATIVE_FOURCC = {b'DXT1', b'DXT3', b'DXT5', b'ATI1', b'ATI2', b'BC4U', b'BC5U'}


def dds_native(data):
    if len(data) < 128 or data[:4] != b'DDS ':
        return False
    flags, fourcc = struct.unpack_from('<I4s', data, 80)
    return bool(flags & 0x4) and fourcc in _NATIVE_FOURCC


def _png(dds_bytes):
    from PIL import Image
    im = Image.open(io.BytesIO(dds_bytes))
    im.load()
    has_alpha = im.mode in ('RGBA', 'LA', 'PA') or 'transparency' in im.info
    buf = io.BytesIO()
    im.convert('RGBA' if has_alpha else 'RGB').save(buf, 'PNG')
    return buf.getvalue()


def material_entry(prefix, vehicle_dir, mat, opacity_file=None, paint=None, files=None):
    tex = mat['textures']
    files = files or {}
    props = mat['props']
    mname = prefix + mat['name']
    spec = props.get('ksSpecular', 0.2)
    stage = {
        'metallicFactor': 1.0 if mat['name'] in METALLIC else 0.0,
        'roughnessFactor': 0.15 if mat['name'] in METALLIC else max(0.25, min(0.9, 0.85 - 0.35 * min(spec, 2.0))),
    }
    if 'txDiffuse' in tex:
        stage['baseColorMap'] = f'/vehicles/{vehicle_dir}/{files.get(tex["txDiffuse"], _texture_file(tex["txDiffuse"]))}'
    normal = tex.get('txNormal', '')
    # Object-space maps (*_OS) and the AC damage normal would shade wrongly as tangent-space.
    if normal and '_os' not in normal.lower() and 'damage' not in normal.lower():
        stage['normalMap'] = f'/vehicles/{vehicle_dir}/{files.get(normal, _texture_file(normal))}'
    if opacity_file:
        stage['opacityMap'] = f'/vehicles/{vehicle_dir}/{opacity_file}'
    entry = {'name': mname, 'mapTo': mname, 'class': 'Material', 'version': 1.5,
             'materialTag0': 'beamng', 'materialTag1': 'vehicle', 'dynamicCubemap': True,
             'Stages': [stage, {}, {}, {}]}
    if paint:
        # Layer 0: car paint from the BeamNG colour picker. Layer 1: AC trim/decal texture on top.
        entry['Stages'] = [
            {'colorPaletteMap': '/vehicles/common/nullcolormaskR.color.png', 'instanceDiffuse': True,
             'metallicFactor': 1, 'roughnessFactor': 0.3, 'clearCoatFactor': 1},
            {'baseColorMap': f'/vehicles/{vehicle_dir}/{paint["base"]}',
             'opacityMap': f'/vehicles/{vehicle_dir}/{paint["opacity"]}',
             'metallicFactor': 0, 'roughnessFactor': 0.5},
            {}, {}]
        entry['activeLayers'] = 2
    elif mat['blend'] == 1:
        entry.update({'translucent': True, 'translucentBlendOp': 'PreMulAlpha', 'castShadows': False})
    elif mat['alpha_test']:
        entry.update({'alphaTest': True, 'alphaRef': 127})
    return mname, entry


def _alpha_png(dds_bytes, invert=False):
    from PIL import Image  # optional dependency, local conversion only
    im = Image.open(io.BytesIO(dds_bytes))
    im.load()
    alpha = im.convert('RGBA').getchannel('A')
    if invert:
        alpha = alpha.point(lambda a: 255 - a)
    buf = io.BytesIO()
    alpha.save(buf, 'PNG')
    return buf.getvalue()


def _rgb_png(dds_bytes):
    from PIL import Image
    im = Image.open(io.BytesIO(dds_bytes))
    im.load()
    buf = io.BytesIO()
    im.convert('RGB').save(buf, 'PNG')
    return buf.getvalue()


def guard_output(out_dir):
    out = Path(out_dir).resolve()
    if out == REPO_ROOT or REPO_ROOT in out.parents:
        raise SystemExit('Refusing to write converted car assets inside the ACNG repository.')
    return out


def export(model, out_vehicle_dir, vehicle_dir, prefix, lift, paint_material='LIVREA'):
    """Write DAE, textures and materials for model (from kn5_model.read). Returns a report dict."""
    out = guard_output(out_vehicle_dir)
    (out / 'textures').mkdir(parents=True, exist_ok=True)
    materials = {m['name']: m for m in model['materials']}
    groups, report = {}, {'meshes': {}, 'skipped': [], 'flipped': []}
    for mesh in model['meshes']:
        target = route(mesh, materials)
        label = '/'.join(mesh['path'])
        if target == SKIP:
            report['skipped'].append(label)
            continue
        pos, nrm, uvs, tris, flipped = convert_mesh(mesh, lift)
        if flipped:
            report['flipped'].append(label)
        name = f'{prefix}{target}'
        g = groups.get(name)
        if g is None or len(g.pos) + len(pos) > MAX_VERTS:
            if g is not None:  # spill into a lettered continuation mesh
                name = name + '_' + 'abcdefgh'[sum(1 for k in groups if k.startswith(name))]
            g = groups[name] = Group(name)
        g.add(mesh['material'], pos, nrm, uvs, tris)
        report['meshes'][label] = name
    used = sorted({m for g in groups.values() for m in g.tris})
    material_names = {m: prefix + m for m in used}
    write_collada(list(groups.values()), out / f'{prefix.rstrip("_")}.dae', material_names)
    written, mats, converted = {}, {}, []
    for m in used:
        mat = materials[m]
        for slot in ('txDiffuse', 'txNormal'):
            t = mat['textures'].get(slot)
            if t and t not in written and t in model['textures']:
                data = model['textures'][t]
                rel = _texture_file(t)
                if not dds_native(data):
                    rel = rel.rsplit('.', 1)[0] + '.png'
                    data = _png(data)
                    converted.append(t)
                (out / rel).write_bytes(data)
                written[t] = rel
        opacity = paint = None
        diffuse = mat['textures'].get('txDiffuse')
        if m == paint_material and diffuse in model['textures']:
            # AC multimap: diffuse alpha 1 = trim/decal, 0 = paint shows through.
            base = f'textures/{prefix}paint_b.color.png'
            opac = f'textures/{prefix}paint_o.data.png'
            (out / base).write_bytes(_rgb_png(model['textures'][diffuse]))
            (out / opac).write_bytes(_alpha_png(model['textures'][diffuse]))
            paint = {'base': base, 'opacity': opac}
        elif (mat['blend'] == 1 or mat['alpha_test']) and diffuse in model['textures']:
            opacity = f'textures/{prefix}{m.lower()}_o.data.png'
            (out / opacity).write_bytes(_alpha_png(model['textures'][diffuse]))
        key, entry = material_entry(prefix, vehicle_dir, mat, opacity, paint, written)
        mats[key] = entry
    (out / 'main.materials.json').write_text(json.dumps(mats, indent=1), encoding='ascii')
    report['groups'] = {g.name: {'vertices': len(g.pos), 'triangles': sum(len(t) for t in g.tris.values()),
                                 'materials': sorted(g.tris)} for g in groups.values()}
    report['textures_written'] = len(written)
    report['textures_converted_png'] = sorted(converted)
    return report
