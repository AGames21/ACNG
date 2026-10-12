"""Write the ACNG Track teal brand kit (original artwork) as SVG, optionally PNG.

    python tools/brand_kit.py           # SVGs into docs/brand/ and the README banner
    python tools/brand_kit.py --png     # also PNG renders via a local Chrome/Edge

Colours (docs/brand/README.md): Carbon base, Teal main, White text, Amber for
small highlights only. The mark is three slanted bars: the inner, middle and
outer tread zones of the ACNG tire model.
"""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BRAND = ROOT / 'docs' / 'brand'
BANNER = ROOT / 'docs' / 'assets' / 'acng-banner.svg'
CARBON, TEAL, WHITE, AMBER = '#121417', '#00D1B2', '#F4F6F5', '#FFB020'
PALETTE = (CARBON, TEAL, WHITE, AMBER)
TAGLINE = 'Racing feel. Open roads. Real consequences.'
DISCLAIMER = 'Unofficial mod. Not affiliated with BeamNG GmbH or Kunos Simulazioni.'
FONT = "font-family=\"'Segoe UI Black','Arial Black',sans-serif\" font-weight=\"900\" font-style=\"italic\""
SANS = "font-family=\"'Segoe UI',Arial,sans-serif\""


def mark(x, y, h, color=TEAL):
    """Three slanted bars of height h with the top-left corner at x, y. Returns (svg, width)."""
    w, gap, lean = h*0.22, h*0.13, h*0.36
    bars = []
    for i in range(3):
        x0 = x + i*(w+gap)
        bars.append(f'<path d="M{x0+lean:.1f} {y:.1f}H{x0+lean+w:.1f}L{x0+w:.1f} {y+h:.1f}H{x0:.1f}Z" fill="{color}"/>')
    return ''.join(bars), 3*w + 2*gap + lean


def svg(w, h, title, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" role="img">'
            f'<title>{title}</title>{body}</svg>\n')


def tag(x, y, text, w, h, size):
    return (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="6" fill="{AMBER}"/>'
            f'<text x="{x+w/2:.0f}" y="{y+h*0.73:.0f}" text-anchor="middle" {SANS} font-size="{size}" font-weight="700" fill="{CARBON}">{text}</text>')


def logo(text):
    m, mw = mark(20, 60, 200)
    return m + f'<text x="{20+mw+30:.0f}" y="245" {FONT} font-size="230" letter-spacing="4" fill="{text}">ACNG</text>'


def title_card():
    m, mw = mark(240, 350, 230)
    return (f'<rect width="1920" height="1080" fill="{CARBON}"/>'
            f'<path d="M1700 0H1920V1080H1420Z" fill="{TEAL}" opacity="0.08"/>'
            f'<path d="M1800 0H1920V1080H1520Z" fill="{TEAL}" opacity="0.10"/>' + m +
            f'<text x="{240+mw+50:.0f}" y="575" {FONT} font-size="265" letter-spacing="6" fill="{WHITE}">ACNG</text>'
            f'<rect x="240" y="650" width="160" height="10" fill="{TEAL}"/>'
            f'<text x="240" y="740" {SANS} font-size="56" font-weight="600" fill="{WHITE}">{TAGLINE}</text>'
            f'<text x="240" y="810" {SANS} font-size="34" fill="{TEAL}">A free BeamNG.drive mod</text>'
            + tag(240, 200, 'BETA', 150, 56, 32) +
            f'<text x="240" y="1000" {SANS} font-size="24" fill="{WHITE}" opacity="0.55">{DISCLAIMER}</text>')


def lower_third(head='TIRE MODEL', sub='Inner, middle and outer tread temperatures'):
    m, mw = mark(150, 838, 40, CARBON)
    return (f'<path d="M120 820H780L762 880H102Z" fill="{TEAL}"/>' + m +
            f'<text x="{150+mw+18:.0f}" y="868" {FONT} font-size="40" fill="{CARBON}">{head}</text>'
            f'<path d="M102 888H962L948 940H88Z" fill="{CARBON}" opacity="0.92"/>'
            f'<text x="130" y="925" {SANS} font-size="30" fill="{WHITE}">{sub}</text>'
            f'<rect x="88" y="948" width="70" height="5" fill="{TEAL}"/>')


def thumbnail(lines=('TIRES', 'THAT HEAT', 'UP')):
    m, mw = mark(60, 60, 56)
    rows = ''.join(f'<text x="60" y="{330+110*i}" {FONT} font-size="92" fill="{TEAL if i == 1 else WHITE}">{t}</text>'
                   for i, t in enumerate(lines))
    return (f'<rect width="1280" height="720" fill="#3a4048"/>'
            f'<text x="900" y="380" text-anchor="middle" {SANS} font-size="28" fill="{WHITE}" opacity="0.5">car shot goes here</text>'
            f'<path d="M0 0H700L560 720H0Z" fill="{CARBON}"/>'
            f'<path d="M700 0H724L584 720H560Z" fill="{TEAL}"/>' + m +
            f'<text x="{60+mw+14:.0f}" y="110" {FONT} font-size="62" fill="{WHITE}">ACNG</text>'
            + rows + tag(60, 610, 'BETA', 130, 48, 28))


def banner():
    m, mw = mark(54, 96, 104)
    chips = ''
    for x, w, text, color in ((54, 170, 'FREEROAM FIRST', TEAL), (236, 160, 'OFF BY DEFAULT', WHITE)):
        chips += (f'<rect x="{x}" y="356" width="{w}" height="36" rx="6" fill="none" stroke="{color}" stroke-opacity="0.7"/>'
                  f'<text x="{x+w/2:.0f}" y="380" text-anchor="middle" {SANS} font-size="13" font-weight="600" letter-spacing="1.5" fill="{color}">{text}</text>')
    return (f'<rect width="1200" height="460" rx="24" fill="{CARBON}"/>'
            f'<path d="M880 0H1176A24 24 0 0 1 1200 24V436A24 24 0 0 1 1176 460H760Z" fill="{TEAL}" opacity="0.08"/>'
            f'<path d="M1010 0H1176A24 24 0 0 1 1200 24V436A24 24 0 0 1 1176 460H890Z" fill="{TEAL}" opacity="0.10"/>'
            f'<text x="56" y="74" {SANS} font-size="13" letter-spacing="4" fill="{TEAL}">A FREE BEAMNG.DRIVE MOD</text>' + m +
            f'<text x="{54+mw+22:.0f}" y="196" {FONT} font-size="120" letter-spacing="3" fill="{WHITE}">ACNG</text>'
            f'<text x="56" y="262" {SANS} font-size="28" font-weight="600" fill="{WHITE}">{TAGLINE}</text>'
            f'<text x="56" y="304" {SANS} font-size="17" fill="{WHITE}" opacity="0.7">AC-style tires and assists. BeamNG suspension, deformation and damage stay in charge.</text>'
            + chips + tag(408, 356, 'BETA', 90, 36, 15) +
            f'<text x="56" y="430" {SANS} font-size="12" fill="{WHITE}" opacity="0.45">{DISCLAIMER}</text>')


SIZES = {'acng-logo': (1080, 300), 'acng-logo-light': (1080, 300), 'acng-icon': (512, 512),
         'acng-title-card': (1920, 1080), 'acng-lower-third': (1920, 1080), 'acng-thumbnail': (1280, 720)}


def build():
    """Return {path: svg text} for every brand file."""
    m, _ = mark(150, 120, 170)
    icon = (f'<rect width="512" height="512" rx="96" fill="{CARBON}"/>' + m +
            f'<text x="256" y="420" text-anchor="middle" {FONT} font-size="118" fill="{WHITE}">ACNG</text>')
    parts = {'acng-logo': ('ACNG logo (dark backgrounds)', logo(WHITE)),
             'acng-logo-light': ('ACNG logo (light backgrounds)', logo(CARBON)),
             'acng-icon': ('ACNG icon', icon),
             'acng-title-card': ('ACNG title card', title_card()),
             'acng-lower-third': ('ACNG lower third', lower_third()),
             'acng-thumbnail': ('ACNG thumbnail template', thumbnail())}
    out = {BRAND / f'{k}.svg': svg(*SIZES[k], t, b) for k, (t, b) in parts.items()}
    out[BANNER] = svg(1200, 460, f'ACNG - {TAGLINE}', banner())
    return out


def find_browser():
    for p in (r'C:\Program Files\Google\Chrome\Application\chrome.exe',
              r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
              r'C:\Program Files\Microsoft\Edge\Application\msedge.exe'):
        if os.path.exists(p):
            return p
    return shutil.which('chrome') or shutil.which('msedge')


def render_png(browser, src, dst, size):
    with tempfile.TemporaryDirectory() as profile:
        subprocess.run([browser, '--headless=new', '--disable-gpu', '--hide-scrollbars', f'--user-data-dir={profile}',
                        '--default-background-color=00000000', f'--window-size={size[0]},{size[1]}',
                        f'--screenshot={dst}', src.resolve().as_uri()], check=True, capture_output=True, timeout=60)


def main(argv):
    files = build()
    BRAND.mkdir(parents=True, exist_ok=True)
    for path, text in files.items():
        path.write_text(text, encoding='ascii', newline='\n')
        print(path.relative_to(ROOT).as_posix())
    if '--png' in argv:
        browser = find_browser()
        if not browser:
            print('No Chrome or Edge found; SVGs written, PNGs skipped.')
            return 1
        for name, size in SIZES.items():
            render_png(browser, BRAND / f'{name}.svg', BRAND / f'{name}.png', size)
            print(f'docs/brand/{name}.png')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
