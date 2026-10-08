"""Read-only KN5 feasibility inventory. Exports no game assets or physics code.

Format reference: RaduMC/kn5-converter, Program.cs (community documentation).
This is an original bounded reader. Only versions 5/6 are supported. Unknown
layouts fail instead of pretending that an empty mesh is a successful import.
"""
import argparse
import hashlib
import json
import struct
from pathlib import Path


class Reader:
    def __init__(self, data):
        self.data = data
        self.offset = 0

    def take(self, size):
        if size < 0 or self.offset + size > len(self.data):
            raise ValueError(f'Truncated KN5 at byte {self.offset}')
        start = self.offset
        self.offset += size
        return self.data[start:self.offset]

    def skip(self, size):
        if size < 0 or self.offset + size > len(self.data):
            raise ValueError(f'Truncated KN5 at byte {self.offset}')
        self.offset += size

    def integer(self):
        return struct.unpack('<I', self.take(4))[0]

    def count(self, maximum=1000000):
        count = self.integer()
        if count > maximum:
            raise ValueError(f'Unreasonable count {count} at byte {self.offset}')
        return count

    def string(self):
        return self.take(self.count(65536)).decode('utf-8', errors='strict')


def inspect(data):
    r = Reader(data)
    if r.take(6) != b'sc6969':
        raise ValueError('Unsupported KN5 signature; no DRM/encryption bypass attempted')
    version = r.integer()
    if version not in (5, 6):
        raise ValueError(f'Unsupported KN5 version {version}')
    if version == 6:
        r.skip(4)
    textures = []
    for _ in range(r.count(10000)):
        kind, name, size = r.integer(), r.string(), r.count(len(data))
        r.skip(size)
        textures.append({'name': name, 'kind': kind, 'bytes': size})
    material_count = r.count(10000)
    materials = []
    for _ in range(material_count):
        name, shader = r.string(), r.string()
        r.skip(6)  # blend/alpha bytes, depth mode
        for _ in range(r.count(10000)):
            r.string()
            r.skip(40)  # scalar and three vectors
        slots = {}
        for _ in range(r.count(10000)):
            slot = r.string()
            r.skip(4)
            slots[slot] = r.string()
        materials.append({'name': name, 'shader': shader, 'textures': slots})
    nodes = []

    def node(depth=0):
        if depth > 128 or len(nodes) >= 100000:
            raise ValueError('Hierarchy limit exceeded')
        kind, name, children = r.integer(), r.string(), r.count(100000)
        active = r.take(1)[0]
        record = {'name': name, 'kind': kind, 'active': bool(active)}
        nodes.append(record)
        if kind == 1:
            r.skip(64)
        elif kind in (2, 3):
            r.skip(3)
            if kind == 3:
                for _ in range(r.count(10000)):
                    r.string()
                    r.skip(64)
            vertices = r.count()
            r.skip(vertices * (44 if kind == 2 else 76))
            indices = r.count(10000000)
            if indices % 3:
                raise ValueError('Non-triangular mesh index count')
            # Validate every index against the mesh, without exporting geometry.
            for (index,) in struct.iter_unpack('<H', r.take(indices * 2)):
                if index >= vertices:
                    raise ValueError('Mesh index out of range')
            material_id = r.integer()
            if material_id >= material_count:
                raise ValueError('Material index out of range')
            r.skip(29 if kind == 2 else 12)
            record.update(vertices=vertices, triangles=indices // 3, material_id=material_id)
        else:
            raise ValueError(f'Unknown KN5 node type {kind}')
        for _ in range(children):
            node(depth + 1)

    node()
    if r.offset != len(data):
        raise ValueError(f'Unparsed trailing bytes: {len(data) - r.offset}')
    meshes = [n for n in nodes if n['kind'] in (2, 3)]
    return {'schema_version': 1, 'format_version': version,
            'source_sha256': hashlib.sha256(data).hexdigest(),
            'bytes_consumed': r.offset, 'textures': textures, 'materials': materials,
            'nodes': nodes, 'mesh_count': len(meshes),
            'vertices': sum(n['vertices'] for n in meshes),
            'triangles': sum(n['triangles'] for n in meshes),
            'exports_game_assets': False, 'driveable_vehicle': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.source.resolve() == args.output.resolve() or args.output.exists():
        parser.error('Output must be a new separate file')
    if args.source.stat().st_size > 1024 * 1024 * 1024:
        parser.error('Input exceeds 1 GiB limit')
    result = inspect(args.source.read_bytes())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(f"KN5 v{result['format_version']}: {result['mesh_count']} meshes, "
          f"{result['triangles']} triangles, {len(result['textures'])} textures; "
          'entire file validated. No assets exported; no driveable vehicle created.')


if __name__ == '__main__':
    main()
