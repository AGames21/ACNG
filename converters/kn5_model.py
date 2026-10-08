"""Bounded KN5 v5/v6 reader that returns geometry for a local, personal conversion.

Format reference: RaduMC/kn5-converter, Program.cs (community documentation).
Original code. Nothing here writes files; see export_kn5.py for the guarded writer.
Unknown or encrypted layouts fail instead of returning partial geometry.
"""
import struct

from inspect_kn5 import Reader


def _matrix(r):
    # Row-major 4x4, row vectors (DirectX style): translation is the last row.
    v = struct.unpack('<16f', r.take(64))
    return [list(v[i * 4:i * 4 + 4]) for i in range(4)]


def _mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


IDENTITY = [[1.0 if i == j else 0.0 for j in range(4)] for i in range(4)]


def transform_point(m, p):
    x, y, z = p
    return tuple(x * m[0][j] + y * m[1][j] + z * m[2][j] + m[3][j] for j in range(3))


def transform_dir(m, d):
    x, y, z = d
    out = [x * m[0][j] + y * m[1][j] + z * m[2][j] for j in range(3)]
    length = sum(c * c for c in out) ** 0.5 or 1.0
    return tuple(c / length for c in out)


def read(data):
    """Return {'textures', 'materials', 'nodes', 'meshes'} with world-space mesh data."""
    r = Reader(data)
    if r.take(6) != b'sc6969':
        raise ValueError('Unsupported KN5 signature; no DRM/encryption bypass attempted')
    version = r.integer()
    if version not in (5, 6):
        raise ValueError(f'Unsupported KN5 version {version}')
    if version == 6:
        r.skip(4)
    textures = {}
    for _ in range(r.count(10000)):
        r.integer()
        name, size = r.string(), r.count(len(data))
        textures[name] = r.take(size)
    materials = []
    for _ in range(r.count(10000)):
        name, shader = r.string(), r.string()
        blend, alpha_test = r.take(1)[0], r.take(1)[0]
        r.skip(4)
        props = {}
        for _ in range(r.count(10000)):
            key = r.string()
            props[key] = struct.unpack('<f', r.take(4))[0]
            r.skip(36)
        slots = {}
        for _ in range(r.count(10000)):
            slot = r.string()
            r.skip(4)
            slots[slot] = r.string()
        materials.append({'name': name, 'shader': shader, 'blend': blend,
                          'alpha_test': alpha_test, 'props': props, 'textures': slots})
    nodes, meshes = [], []

    def node(parent_world, path, depth=0):
        if depth > 128 or len(nodes) >= 100000:
            raise ValueError('Hierarchy limit exceeded')
        kind, name, children = r.integer(), r.string(), r.count(100000)
        active = bool(r.take(1)[0])
        here = path + [name]
        world = parent_world
        if kind == 1:
            local = _matrix(r)
            world = _mul(local, parent_world)
            nodes.append({'name': name, 'path': here, 'world': world, 'active': active})
        elif kind in (2, 3):
            cast_shadows, visible, transparent = r.take(3)
            if kind == 3:
                for _ in range(r.count(10000)):
                    r.string()
                    r.skip(64)
            count = r.count()
            stride = 44 if kind == 2 else 76
            raw = r.take(count * stride)
            positions, normals, uvs = [], [], []
            for i in range(count):
                px, py, pz, nx, ny, nz, u, v = struct.unpack_from('<8f', raw, i * stride)
                # Skinned vertices are stored in mesh space too; bones are ignored (static pose).
                positions.append(transform_point(parent_world, (px, py, pz)))
                normals.append(transform_dir(parent_world, (nx, ny, nz)))
                uvs.append((u, v))
            index_count = r.count(10000000)
            if index_count % 3:
                raise ValueError('Non-triangular mesh index count')
            indices = list(struct.unpack(f'<{index_count}H', r.take(index_count * 2)))
            if any(i >= count for i in indices):
                raise ValueError('Mesh index out of range')
            material_id = r.integer()
            if material_id >= len(materials):
                raise ValueError('Material index out of range')
            r.skip(29 if kind == 2 else 12)
            meshes.append({'name': name, 'path': here, 'material': materials[material_id]['name'],
                           'visible': bool(visible), 'active': active, 'skinned': kind == 3,
                           'positions': positions, 'normals': normals, 'uvs': uvs,
                           'indices': indices})
        else:
            raise ValueError(f'Unknown KN5 node type {kind}')
        for _ in range(children):
            node(world, here, depth + 1)

    node(IDENTITY, [])
    if r.offset != len(data):
        raise ValueError(f'Unparsed trailing bytes: {len(data) - r.offset}')
    return {'format_version': version, 'textures': textures, 'materials': materials,
            'nodes': nodes, 'meshes': meshes}
