"""Engine and exhaust sound for the local AC car conversion.

Reads the PCM16 loops from the user's own AC FMOD bank (an FSB5 inside an unencrypted RIFF
bank), writes them as mono WAVs plus BeamNG `.sfxBlend2D.json` rpm blends into the build
output only, and points the cloned engine part at them. Nothing here is committed or shipped.
"""
import json
import math
import re
import shutil
import struct
import wave
from pathlib import Path

RATES = {1: 8000, 2: 11000, 3: 11025, 4: 16000, 5: 22050, 6: 24000, 7: 32000, 8: 44100, 9: 48000}
# Measured, not named: the idle loops' firing-frequency envelopes put them at 630-675 rpm (I6 fires
# three times per rev). Tagging them 800 played the idle 19 % flat at the 650 rpm engine idle.
IDLE_RPM = 650
PREFIX, LABEL = 'acng_1m_', '1M'  # per-car names (converters/cars/ profiles override the constants here)
# Optional explicit loop order per set: {key: (off-load names, on-load names)}. Needed when a
# bank's names do not sort into AC's play order (the M3's on_4198 plays below its on_4000).
CHAINS = {}
# Idle loop tag per set when the sets' idles were recorded at different speeds.
IDLE_TAGS = {}
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
# AC holds each loop alone over a wide rpm band and crossfades to the next one over 400 rpm
# (1200 for one idle). Read from the 1M bank's event metadata: each loop instrument's fade-in
# and fade-out curves and its volume. A BeamNG blend crossfades linearly between neighbouring
# entries, so with one entry per loop two different recordings played together across the whole
# gap (C011 playtest: "switches to a different sound around 2500"). Each loop now gets pitched
# copies at both edges of its band, so BeamNG only crossfades inside AC's windows.
# Per set, (off-load, on-load): {loop rpm: (fade-in window from the loop below, AC volume dB)}.
AC_LAYOUT = {
    'engine': ({IDLE_RPM: (None, -3.5), 2000: ((1200, 2400), -4.5), 4000: ((2600, 3000), -2),
                6000: ((4000, 4400), -2.5), 8000: ((5600, 6000), -2)},
               {IDLE_RPM: (None, 0), 2800: ((1600, 2000), -2.5), 4000: ((2800, 3200), -3),
                6000: ((4000, 4400), -3), 8000: ((6000, 6400), -3)}),
    'exhaust': ({IDLE_RPM: (None, -3), 2500: ((1800, 2200), 0), 4500: ((2600, 3000), 0),
                 6000: ((4400, 4800), 0), 8000: ((5600, 6000), 0)},
                {IDLE_RPM: (None, -1.5), 2500: ((1600, 2000), -2), 4000: ((2600, 3000), -3),
                 5500: ((4000, 4400), -3), 8000: ((5600, 6000), -3)}),
}
XFADE_RPM = 400
# Pitched copies of one loop must stay in step when BeamNG mixes them, so their lengths are
# chosen to make the tag rpm (nearly) a whole number; the tag may move this much to find one.
TAG_SLACK = 0.003
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


def loops(samples):
    """Map each sound set to (off-load, on-load) rpm-sorted lists of (recorded rpm, sample name)."""
    out = {}
    for key, spec in SETS.items():
        lists = []
        idle = IDLE_TAGS.get(key, IDLE_RPM)
        if key in CHAINS:
            chains = [[(idle if n == spec['idle'] else int(re.search(r'(\d+)$', n).group(1)), n)
                       for n in chain if n in samples] for chain in CHAINS[key]]
            if all(chains):
                out[key] = chains
            continue
        for prefix in (spec['prefix_off'], spec['prefix_on']):
            rows = [(int(n[len(prefix):]), n) for n in samples if n.startswith(prefix) and n[len(prefix):].isdigit()]
            if spec['idle'] in samples:
                rows.append((idle, spec['idle']))
            lists.append(sorted(rows))
        if all(lists):
            out[key] = lists
    return out


def layout(key, load, rpm):
    """(fade-in window, volume dB) for the loop recorded at `rpm`; (None, 0) when AC's is unknown."""
    return AC_LAYOUT.get(key, ({}, {}))[load].get(rpm, (None, 0))


def zone(key, load, lower, upper):
    """The rpm window where loop `lower` hands over to loop `upper` (AC's, else a centred 400)."""
    window = layout(key, load, upper)[0]
    if window and window[0] < window[1]:  # AC's may end below `lower` or above `upper`
        return window
    mid = (lower + upper) / 2
    return round(mid - XFADE_RPM / 2), round(mid + XFADE_RPM / 2)


def blends(samples):
    """Map each sound set to (off-load, on-load) lists of (tag rpm, sample name, recorded rpm, dB).

    Each loop appears at both edges of the band where it plays alone; BeamNG's linear blend then
    only mixes two different recordings inside AC's crossfade windows.
    """
    out = {}
    for key, lists in loops(samples).items():
        out[key] = []
        for load, rows in enumerate(lists):
            entries = []
            for i, (rpm, name) in enumerate(rows):
                lo = zone(key, load, rows[i - 1][0], rpm)[1] if i else rpm
                hi = zone(key, load, rpm, rows[i + 1][0])[0] if i + 1 < len(rows) else rpm
                db = layout(key, load, rpm)[1]
                entries += [(lo, name, rpm, db)] + ([(max(hi, lo + 1), name, rpm, db)] if hi != lo else [])
            out[key].append(entries)
    return out


def gain(pcm, db):
    if not db:
        return pcm
    k = 10 ** (db / 20)
    vals = struct.unpack(f'<{len(pcm) // 2}h', pcm)
    return struct.pack(f'<{len(vals)}h', *(max(-32768, min(32767, round(v * k))) for v in vals))


def copy_length(n, rpm, tag):
    """Frames for a copy of an n-frame loop recorded at `rpm` re-pitched to play at `tag`.

    Returns (frames, whole-number tag) with frames chosen so rpm * n / frames is nearly whole:
    then every copy runs through the source in step when BeamNG plays them at rpm / tag.
    """
    if tag == rpm:
        return n, rpm
    ideal = n * rpm / tag
    # Lengths whose tag stays within TAG_SLACK of the wanted one (tag falls as the length grows).
    lo, hi = math.ceil(n * rpm / (tag * (1 + TAG_SLACK))), math.floor(n * rpm / (tag * (1 - TAG_SLACK)))
    frames = min(range(max(lo, 1), max(hi, lo, 1) + 1), key=lambda f: (abs(rpm * n / f - round(rpm * n / f)), abs(f - ideal)))
    return frames, round(rpm * n / frames)


def repitch(pcm, frames):
    """Resample a mono loop to `frames` frames, wrapping round the loop point (no seam)."""
    vals = struct.unpack(f'<{len(pcm) // 2}h', pcm)
    n = len(vals)
    step = n / frames
    width = int(round(step))
    if width > 1:  # shortening raises the pitch: average first so it doesn't alias
        ext = vals[-(width // 2):] + vals + vals[:width]  # centred window, wrapping round the loop
        acc, run = [0], 0
        for v in ext:
            run += v
            acc.append(run)
        vals = [(acc[i + width] - acc[i]) / width for i in range(n)]
    out = []
    for j in range(frames):
        x = j * step
        i = int(x)
        f = x - i
        out.append(max(-32768, min(32767, round(vals[i % n] * (1 - f) + vals[(i + 1) % n] * f))))
    return struct.pack(f'<{frames}h', *out)


def write(bank, vdir, vehicle):
    """Write WAVs and blends under vdir/sounds; return the engine-part sound key updates."""
    samples = read_fsb(bank.read_bytes())
    sdir, folder = vdir / 'sounds', f'vehicles/{vehicle}/sounds/'
    sdir.mkdir(exist_ok=True)
    names, clean, done = {}, {}, {}
    for key, lists in blends(samples).items():
        blend_rows = []
        for entries in lists:
            rows = []
            for tag, n, rpm, db in entries:
                if n not in clean:
                    rate, ch, pcm = samples[n]
                    clean[n] = (rate, seamless(mono(pcm, ch), rate))
                rate, pcm = clean[n]
                frames, exact = copy_length(len(pcm) // 2, rpm, tag)
                file = n + (f'_at_{exact}' if exact != rpm else '') + (f'_{db:+g}dB' if db else '') + '.wav'
                if file not in done:
                    out = pcm if frames * 2 == len(pcm) else repitch(pcm, frames)
                    (sdir / file).write_bytes(wav(gain(out, db), rate))
                    done[file] = exact
                rows.append([folder + file, exact])
            blend_rows.append(rows)
        blend = {'header': {'version': 1}, 'eventName': 'event:>Engine>default', 'samples': blend_rows}
        names[key] = PREFIX + key
        (sdir / f'{names[key]}.sfxBlend2D.json').write_text(json.dumps(blend, indent=1), encoding='ascii')
    return {key: {'sampleFolder': folder, 'sampleName': name, 'offLoadGain': OFF_LOAD_GAIN, **FLAT_EQ}
            for key, name in names.items()}


EVENT_SAMPLES = ('turbo', 'flutter_4', 'bmw_6cyl_limiter', 'gearup', 'geardn')
SEAMLESS_EVENTS = {'turbo'}  # looped events get the click-free seam
# Hooks: (part suffix, section, field, event sample). Gear sounds go to ACNG's controller below.
EVENT_HOOKS = (('turbo', 'turbocharger', 'whineLoopEvent', 'turbo'),
               ('turbo', 'turbocharger', 'bovSoundFileName', 'flutter_4'),
               ('shifter', 'acng_shiftSound', 'upSample', 'gearup'),
               ('shifter', 'acng_shiftSound', 'downSample', 'geardn'))
# Hooks into this section feed ACNG's own vehicle controller (converters/vehicle_lua): native
# playSFXOnceCT takes FMOD events only, so a WAV on a native lever hook is never heard.
SHIFT_SECTION = 'acng_shiftSound'
SHIFT_LUA = Path(__file__).resolve().parent / 'vehicle_lua' / 'acng_shiftSound.lua'


def write_events(bank, vdir, vehicle):
    """Export owned recordings separately; never alter engine/exhaust blends.

    BeamNG 0.39 has no standalone combustion-engine rev-limiter sample slot.
    Preserve that recording locally for research, without pretending it is wired.
    """
    samples = read_fsb(bank.read_bytes())
    missing = set(EVENT_SAMPLES) - samples.keys()
    if missing:
        raise ValueError(f'Missing {LABEL} event samples: ' + ', '.join(sorted(missing)))
    sdir = vdir / 'sounds'
    sdir.mkdir(exist_ok=True)
    files = {}
    for name in EVENT_SAMPLES:
        rate, channels, pcm = samples[name]
        pcm = mono(pcm, channels)
        if name in SEAMLESS_EVENTS:
            pcm = seamless(pcm, rate)
        filename = PREFIX + name + '.wav'
        (sdir / filename).write_bytes(wav(pcm, rate))
        files[name] = 'vehicles/' + vehicle + '/sounds/' + filename
    return files


def apply_events(parts, files, vdir=None):
    """Point the hooks (EVENT_HOOKS) at the exported samples; retain mechanical values.

    The shift controller plays upSample on a higher gear and downSample on a lower one.
    A SHIFT_SECTION hook (`upSample`/`downSample`) also gets the recording's length
    (`upSeconds`/`downSeconds`) and installs the controller under vdir/lua/controller.
    No unsupported revLimiterSound property is installed.
    """
    for suffix, section, field, sample in EVENT_HOOKS:
        data = parts[PREFIX + suffix][section]
        data[field] = files[sample]
        if section == SHIFT_SECTION:
            with wave.open(str(vdir / 'sounds' / Path(files[sample]).name)) as w:
                data[field.replace('Sample', 'Seconds')] = round(w.getnframes() / w.getframerate(), 3)
            target = vdir / 'lua' / 'controller'
            target.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(SHIFT_LUA, target / SHIFT_LUA.name)


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
