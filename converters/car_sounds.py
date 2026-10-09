"""Engine and exhaust sound for the local AC car conversion.

Reads the PCM16 loops from the user's own AC FMOD bank (an FSB5 inside an unencrypted RIFF
bank), writes them as mono WAVs plus BeamNG `.sfxBlend2D.json` rpm blends into the build
output only, and points the cloned engine part at them. Nothing here is committed or shipped.
"""
import json
import math
import struct

RATES = {1: 8000, 2: 11000, 3: 11025, 4: 16000, 5: 22050, 6: 24000, 7: 32000, 8: 44100, 9: 48000}
# Measured, not named: the idle loops' firing-frequency envelopes put them at 630-675 rpm (I6 fires
# three times per rev). Tagging them 800 played the idle 19 % flat at the 650 rpm engine idle.
IDLE_RPM = 650
# AC 1M bank sample names: the interior set drives the engine node, the exterior set the exhaust.
# Both are full-car recordings, so at equal level the car played two engines from two positions
# (C010 playtest: "weird and artificial"). The exterior set leads; the interior set stays as a
# quiet cabin/mechanical layer.
TRIM_DB = {'soundConfig': -8, 'soundConfigExhaust': 0}
# The AC off-throttle loops already sit 3.5-4.5 dB under the on-throttle ones; the donor's
# offLoadGain 0.5 cut a further 6 dB on top, so lifting off dropped the sound away.
OFF_LOAD_GAIN = 0.75
SETS = {
    'engine': {'idle': '1m_idle', 'prefix_on': '1m_on_', 'prefix_off': '1m_off_'},
    'exhaust': {'idle': 'ext_1m_idle', 'prefix_on': 'ext1m_on_', 'prefix_off': 'ext1m_off_'},
}
# The donor ETK I6 heavily EQs synthetic loops; the AC loops are finished recordings, so flat.
FLAT_EQ = {'lowShelfGain': 0, 'highShelfGain': 0, 'eqLowGain': 0, 'eqHighGain': 0, 'eqFundamentalGain': 0}
# Child parts still add EQ with "$+" keys (turbo intake +4 dB fundamental, I6 exhaust +12 dB
# low shelf / -9 dB high shelf), so a flat base was not flat in game. Undoing that EQ drops the
# average A-weighted level about 3.6 dB (engine) and 4.1 dB (exhaust); win most of it back.
LEVEL_MATCH_DB = 3
# A loop whose end-to-start jump is this many times its mean step clicks (ext_1m_idle: 7.3).
SEAM_RATIO = 2
FADE_S = 0.03


def read_fsb(data):
    """Return {name: (rate, channels, pcm16 bytes)} from the first FSB5 in `data` (PCM16 only)."""
    i = data.find(b'FSB5')
    if i < 0:
        raise ValueError('no FSB5 sound bank found')
    version, count, headers, names_size, _, mode = struct.unpack('<6I', data[i + 4:i + 28])
    if mode != 2:
        raise ValueError(f'FSB5 mode {mode} is not PCM16')
    pos = i + (60 if version == 1 else 64)
    names_at = pos + headers
    sample_data = names_at + names_size
    offsets = struct.unpack(f'<{count}I', data[names_at:names_at + 4 * count])
    out = {}
    for k in range(count):
        v = struct.unpack('<Q', data[pos:pos + 8])[0]
        pos += 8
        more = v & 1
        while more:  # optional chunks (loop, peak, ...); not needed for whole-file loops
            c = struct.unpack('<I', data[pos:pos + 4])[0]
            more, pos = c & 1, pos + 4 + ((c >> 1) & 0xFFFFFF)
        rate, channels = RATES[(v >> 1) & 0xF], ((v >> 5) & 1) + 1
        start = sample_data + ((v >> 7) & 0x3FFFFFF) * 32
        name_at = names_at + offsets[k]
        name = data[name_at:data.index(b'\0', name_at)].decode('ascii')
        out[name] = (rate, channels, data[start:start + (v >> 34) * 2 * channels])
    return out


def mono(pcm, channels):
    if channels == 1:
        return pcm
    vals = struct.unpack(f'<{len(pcm) // 2}h', pcm)
    mixed = [sum(vals[j:j + channels]) // channels for j in range(0, len(vals), channels)]
    return struct.pack(f'<{len(mixed)}h', *mixed)


def seam_ratio(vals):
    step = sum(abs(b - a) for a, b in zip(vals, vals[1:])) / max(len(vals) - 1, 1)
    return abs(vals[0] - vals[-1]) / (step or 1)


def seamless(pcm, rate):
    """Remove a loop-point click: crossfade the tail into the head (equal power), else unchanged."""
    vals = struct.unpack(f'<{len(pcm) // 2}h', pcm)
    n = int(rate * FADE_S)
    if len(vals) < 4 * n or seam_ratio(vals) <= SEAM_RATIO:
        return pcm
    body, tail = vals[:-n], vals[-n:]
    head = []
    for i in range(n):
        t = (i + 0.5) / n * math.pi / 2
        head.append(max(-32768, min(32767, round(body[i] * math.sin(t) + tail[i] * math.cos(t)))))
    out = head + list(body[n:])
    return struct.pack(f'<{len(out)}h', *out)


def wav(pcm, rate):
    return (b'RIFF' + struct.pack('<I', 36 + len(pcm)) + b'WAVEfmt ' +
            struct.pack('<IHHIIHH', 16, 1, 1, rate, rate * 2, 2, 16) + b'data' + struct.pack('<I', len(pcm)) + pcm)


def blends(samples):
    """Map each sound set to (off-load, on-load) rpm-sorted lists of sample names."""
    out = {}
    for key, spec in SETS.items():
        lists = []
        for prefix in (spec['prefix_off'], spec['prefix_on']):
            rows = [(int(n[len(prefix):]), n) for n in samples if n.startswith(prefix) and n[len(prefix):].isdigit()]
            if spec['idle'] in samples:
                rows.append((IDLE_RPM, spec['idle']))
            lists.append(sorted(rows))
        if all(lists):
            out[key] = lists
    return out


def write(bank, vdir, vehicle):
    """Write WAVs and blends under vdir/sounds; return the engine-part sound key updates."""
    samples = read_fsb(bank.read_bytes())
    sdir, folder = vdir / 'sounds', f'vehicles/{vehicle}/sounds/'
    sdir.mkdir(exist_ok=True)
    names = {}
    for key, lists in blends(samples).items():
        for rows in lists:
            for _, n in rows:
                rate, ch, pcm = samples[n]
                (sdir / f'{n}.wav').write_bytes(wav(seamless(mono(pcm, ch), rate), rate))
        blend = {'header': {'version': 1}, 'eventName': 'event:>Engine>default',
                 'samples': [[[folder + f'{n}.wav', rpm] for rpm, n in rows] for rows in lists]}
        names[key] = f'acng_1m_{key}'
        (sdir / f'{names[key]}.sfxBlend2D.json').write_text(json.dumps(blend, indent=1), encoding='ascii')
    return {key: {'sampleFolder': folder, 'sampleName': name, 'offLoadGain': OFF_LOAD_GAIN, **FLAT_EQ}
            for key, name in names.items()}


def donor_offsets(parts, chosen):
    """Sum the "$+" sound EQ keys that the chosen child parts add on top of the engine's values."""
    out = {'soundConfig': {}, 'soundConfigExhaust': {}}
    for name in sorted(set(chosen)):
        for section, add in out.items():
            for k, v in parts.get(name, {}).get(section, {}).items():
                key = k[2:]
                if k.startswith('$+') and key in FLAT_EQ and isinstance(v, (int, float)):
                    add[key] = add.get(key, 0) + v
    return out


def apply(engine, updates, offsets=None):
    """Point a cloned engine part's soundConfig/soundConfigExhaust at the AC blends.

    With `offsets` from donor_offsets the base EQ cancels the child parts, so the final EQ is flat.
    """
    for key, section in (('engine', 'soundConfig'), ('exhaust', 'soundConfigExhaust')):
        if key in updates:
            ref = engine['mainEngine'].get(section, section)
            config = engine.setdefault(ref, {})
            config.update(updates[key])
            if offsets is not None:
                config.update({k: -v for k, v in offsets.get(section, {}).items() if v})
                config['mainGain'] = config.get('mainGain', 0) + LEVEL_MATCH_DB + TRIM_DB[section]
    return engine
