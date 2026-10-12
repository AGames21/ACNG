"""Cut a short ACNG dev video from film_lab clips: brand title card, sped-up clips with a
lower third, a zoomed tire HUD inset and an "unofficial mod" label, then an end card.

    python tools/cut_short.py tools/shorts/tires-v1.json --clip heat=<film>/tireheat-heat.mp4 \
        --clip cool=<film>/tireheat-cool.mp4 --clip dirt=<film>/tiredirt-dirt.mp4 --out <work>/acng-tires-v1.mp4

The plan (JSON) lists segments: {"kind": "card", "seconds": s} or {"kind": "clip", "clip": name,
"start": s, "end": s, "speed": x, "head": text, "sub": text, "inset": bool}. Clip paths are given
on the command line so personal paths stay out of the repository; video never goes in it.
Use --size 2560x1440 --audio for v2; the separate game audio stream stays mutable. Music is the maintainer's pick. Needs ffmpeg on PATH (or --ffmpeg) and
Chrome or Edge for the overlays (rendered from the brand kit SVG helpers).
"""
import argparse
import contextlib
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import brand_kit as bk  # noqa: E402

W, H = 1920, 1080
# The tire tiles in a film_lab recording at 1920x1080 (minimal_hud placement): x, y, w, h.
HUD_BOX = (1650, 780, 262, 240)
ZOOM = 3
INSET_XY = (W - HUD_BOX[2]*ZOOM - 60, 300)
FADE = 0.25
LABEL = 'UNOFFICIAL MOD · BETA · STOCK CAR, LAB TEST'


def configure_size(width,height):
    global W,H,HUD_BOX,INSET_XY,ZOOM
    if width<1280 or height<720:raise ValueError('Video must be at least 1280x720')
    W,H=width,height
    scale=height/1080
    HUD_BOX=(round((width/scale-270)*scale),round(780*scale),round(262*scale),round(240*scale))
    ZOOM=2 if height>=1440 else 3
    INSET_XY=(W-HUD_BOX[2]*ZOOM-60,round(H*0.28))


def audio_tempo(speed):
    if speed<=0:raise ValueError('speed must be positive')
    factors=[]
    while speed>2:factors.append(2);speed/=2
    while speed<0.5:factors.append(0.5);speed/=0.5
    factors.append(speed)
    return ','.join(f'atempo={x:g}' for x in factors)


def parse_clip(text):
    name, sep, path = text.partition('=')
    if not sep or not name or not path:
        raise argparse.ArgumentTypeError('expected name=path')
    return name, Path(path)


def speed_text(speed):
    return f'{speed:g}x SPEED' if speed != 1 else 'REAL TIME'


def overlay_svg(seg):
    """Full-frame transparent overlay for one clip segment."""
    lt = f'<g transform="scale({W/1920},{H/1080})">'+bk.lower_third(escape(seg['head']), escape(seg['sub']))+'</g>'
    body = [lt,
            f'<rect x="60" y="56" width="620" height="44" rx="6" fill="{bk.CARBON}" opacity="0.85"/>',
            f'<text x="80" y="86" {bk.SANS} font-size="22" font-weight="600" letter-spacing="1" fill="{bk.WHITE}">'
            f'{escape(LABEL)}</text>',
            bk.tag(700, 56, speed_text(seg.get('speed', 1)), 170, 44, 22)]
    if seg.get('inset'):
        x, y = INSET_XY
        w, h = HUD_BOX[2]*ZOOM, HUD_BOX[3]*ZOOM
        body += [f'<rect x="{x-6}" y="{y-6}" width="{w+12}" height="{h+12}" rx="10" fill="none" stroke="{bk.TEAL}" stroke-width="6"/>',
                 f'<rect x="{x-6}" y="{y-54}" width="300" height="44" rx="6" fill="{bk.TEAL}"/>',
                 f'<text x="{x+12}" y="{y-23}" {bk.FONT} font-size="26" fill="{bk.CARBON}">LIVE TIRE HUD</text>']
    return bk.svg(W, H, 'ACNG video overlay', ''.join(body))


def validate(plan, clips):
    segs = plan.get('segments') or []
    if not segs:
        raise ValueError('plan has no segments')
    for i, seg in enumerate(segs):
        kind = seg.get('kind')
        if kind == 'card':
            if not seg.get('seconds', 0) > 0:
                raise ValueError(f'segment {i}: card needs seconds > 0')
        elif kind == 'clip':
            if seg.get('clip') not in clips:
                raise ValueError(f"segment {i}: no --clip given for {seg.get('clip')!r}")
            if not (seg.get('end', 0) > seg.get('start', 0) >= 0 and seg.get('speed', 1) > 0):
                raise ValueError(f'segment {i}: needs 0 <= start < end and speed > 0')
            if not seg.get('head') or not seg.get('sub'):
                raise ValueError(f'segment {i}: needs head and sub')
        else:
            raise ValueError(f'segment {i}: unknown kind {kind!r}')
    return segs


def seg_seconds(seg):
    if seg['kind'] == 'card':
        return float(seg['seconds'])
    return (seg['end'] - seg['start']) / seg.get('speed', 1)


def fades(dur):
    return f'fade=t=in:st=0:d={FADE},fade=t=out:st={max(0, dur-FADE):.3f}:d={FADE}'


ENCODE = ['-c:v', 'libx264', '-preset', 'medium', '-crf', '18', '-pix_fmt', 'yuv420p']


def card_args(ffmpeg, card, dur, fps, out, audio=False):
    return [ffmpeg, '-v', 'error', '-y', '-loop', '1', '-framerate', str(fps), '-t', f'{dur:.3f}', '-i', str(card),
            *( ['-f','lavfi','-i','anullsrc=r=48000:cl=stereo','-shortest','-c:a','aac','-b:a','192k'] if audio else ['-an']),
            '-vf', f'scale={W}:{H},format=yuv420p,{fades(dur)}', '-t', f'{dur:.3f}', '-r', str(fps), *ENCODE, str(out)]


def clip_args(ffmpeg, seg, src, overlay, fps, out, audio=False):
    dur = seg_seconds(seg)
    x, y, w, h = HUD_BOX
    chain = f"[0:v]setpts=(PTS-STARTPTS)/{seg.get('speed', 1)},fps={fps},scale={W}:{H}"
    if seg.get('inset'):
        ix, iy = INSET_XY
        graph = (f'{chain},split=2[base][hud];[hud]crop={w}:{h}:{x}:{y},scale={w*ZOOM}:{h*ZOOM}:flags=lanczos[zoom];'
                 f'[base][zoom]overlay={ix}:{iy}[v1];[v1][1:v]overlay=0:0,format=yuv420p,{fades(dur)}[v]')
    else:
        graph = f'{chain}[v1];[v1][1:v]overlay=0:0,format=yuv420p,{fades(dur)}[v]'
    if audio:
        graph += f';[0:a]asetpts=PTS-STARTPTS,{audio_tempo(seg.get("speed",1))},apad,atrim=duration={dur:.3f},afade=t=in:d=0.15,afade=t=out:st={max(0,dur-0.15):.3f}:d=0.15[a]'
    return [ffmpeg, '-v', 'error', '-y', '-ss', f"{seg['start']:.3f}", '-to', f"{seg['end']:.3f}", '-i', str(src),
            '-i', str(overlay), '-filter_complex', graph, '-map', '[v]', '-t', f'{dur:.3f}', '-r', str(fps),
            *(['-map','[a]','-c:a','aac','-b:a','192k','-metadata:s:a:0','title=BeamNG game audio'] if audio else ['-an']),
            *ENCODE, str(out)]


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('plan', type=Path)
    ap.add_argument('--clip', type=parse_clip, action='append', default=[], help='name=path (repeatable)')
    ap.add_argument('--out', type=Path, required=True)
    ap.add_argument('--fps', type=int, default=60)
    ap.add_argument('--size',default='1920x1080')
    ap.add_argument('--audio',action='store_true',help='preserve separate game audio stream')
    ap.add_argument('--nvenc',action='store_true',help='use verified NVENC encoder, with x264 fallback')
    ap.add_argument('--ffmpeg', default=shutil.which('ffmpeg'))
    args = ap.parse_args(argv)
    if not args.ffmpeg:
        ap.error('ffmpeg not found')
    if args.nvenc:
        from film_lab import encoder_args
        global ENCODE
        ENCODE=encoder_args(args.ffmpeg)+['-pix_fmt','yuv420p']
    browser = bk.find_browser()
    if not browser:
        ap.error('Chrome or Edge is needed to render the overlays')
    width,height=map(int,args.size.split('x'))
    configure_size(width,height)
    clips = dict(args.clip)
    plan = json.loads(args.plan.read_text(encoding='utf-8'))
    segs = validate(plan, clips)
    for name, path in clips.items():
        if not path.exists():
            ap.error(f'clip {name}: {path} not found')
    if ROOT in args.out.resolve().parents:
        ap.error('video stays outside the repository')
    args.out.parent.mkdir(parents=True, exist_ok=True)
    card = bk.BRAND / 'acng-title-card.png'
    # Keep generated intermediates outside Git; no deletion without user approval.
    with contextlib.nullcontext(tempfile.mkdtemp(prefix='acng-cut-', dir=args.out.parent)) as tmp:
        tmp = Path(tmp)
        parts = []
        for i, seg in enumerate(segs):
            out = tmp / f'part{i:02d}.mp4'
            if seg['kind'] == 'card':
                cmd = card_args(args.ffmpeg, card, seg_seconds(seg), args.fps, out, args.audio)
            else:
                svg_path, png = tmp / f'overlay{i:02d}.svg', tmp / f'overlay{i:02d}.png'
                svg_path.write_text(overlay_svg(seg), encoding='utf-8')
                bk.render_png(browser, svg_path, png, (W, H))
                cmd = clip_args(args.ffmpeg, seg, clips[seg['clip']], png, args.fps, out, args.audio)
            subprocess.run(cmd, check=True)
            parts.append(out)
            print(f"part {i}: {seg['kind']} {seg.get('clip', '')} {seg_seconds(seg):.1f}s")
        listing = tmp / 'parts.txt'
        listing.write_text(''.join(f"file '{p.as_posix()}'\n" for p in parts), encoding='utf-8')
        subprocess.run([args.ffmpeg, '-v', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', str(listing),
                        '-c', 'copy', *(['-metadata:s:a:0','handler_name=BeamNG game audio'] if args.audio else []),
                        '-movflags', '+faststart', str(args.out)], check=True)
    print(f'{args.out} {sum(seg_seconds(s) for s in segs):.1f}s')
    return 0


if __name__ == '__main__':
    sys.exit(main())
