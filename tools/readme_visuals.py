"""Original README graphics extending the existing Track teal mark."""
from pathlib import Path
from brand_kit import mark,svg,CARBON,TEAL,WHITE,AMBER
ROOT=Path(__file__).resolve().parents[1]
def banner_body():
 m,_=mark(55,90,112)
 return (f'<rect width="1200" height="460" rx="24" fill="{CARBON}"/>'
  f'<path d="M940 0H1200V460H750Z" fill="{TEAL}" opacity=".07"/>'+m+
  f'<text x="245" y="197" font-family="Segoe UI,Arial,sans-serif" font-size="110" font-weight="900" font-style="italic" fill="{WHITE}">ACNG</text>'
  f'<text x="55" y="272" font-family="Segoe UI,Arial,sans-serif" font-size="32" fill="{WHITE}">Racing feel. Open roads. Real consequences.</text>'
  f'<text x="55" y="315" font-family="Segoe UI,Arial,sans-serif" font-size="20" fill="{TEAL}">Tire heat / pressure / wear / dirt</text>'
  f'<rect x="55" y="365" width="200" height="40" rx="20" fill="{TEAL}"/>'
  f'<text x="155" y="391" text-anchor="middle" font-family="Segoe UI,Arial,sans-serif" font-size="14" font-weight="700" fill="{CARBON}">FREEROAM FIRST</text>'
  f'<rect x="272" y="365" width="182" height="40" rx="20" fill="none" stroke="{WHITE}" opacity=".8"/>'
  f'<text x="363" y="391" text-anchor="middle" font-family="Segoe UI,Arial,sans-serif" font-size="14" fill="{WHITE}">ONE SMALL SWITCH</text>'
  f'<rect x="1000" y="42" width="145" height="34" rx="17" fill="{AMBER}"/>'
  f'<text x="1072" y="65" text-anchor="middle" font-family="Segoe UI,Arial,sans-serif" font-size="14" font-weight="700" fill="{CARBON}">0.3.1 BETA</text>'
  f'<circle cx="1000" cy="235" r="116" fill="none" stroke="{WHITE}" stroke-width="22" opacity=".12"/>'
  f'<circle cx="1000" cy="235" r="84" fill="none" stroke="{TEAL}" stroke-width="9" opacity=".75"/>'
  f'<path d="M943 187L972 169L1055 277L1026 295Z" fill="{TEAL}"/><path d="M977 167L1001 163L1070 253L1057 278Z" fill="{AMBER}" opacity=".8"/>'
  f'<text x="1000" y="392" text-anchor="middle" font-family="Segoe UI,Arial,sans-serif" font-size="13" fill="{WHITE}" opacity=".6">AC-INSPIRED. BUILT FOR BEAMNG.</text>'
  f'<text x="55" y="443" font-family="Segoe UI,Arial,sans-serif" font-size="12" fill="{WHITE}" opacity=".5">Unofficial mod. Not affiliated with BeamNG GmbH or Kunos Simulazioni.</text>')
def overview():
 out=f'<rect width="1200" height="250" rx="18" fill="{CARBON}"/>'
 cards=[('FEEL THE TIRES',['Three tread temperatures','Pressure, compounds and grip'],TEAL),('DRIVE WITH CONSEQUENCES',['Dirt, graining and blistering','Wear down to a native puncture'],AMBER),('MAKE IT YOURS',['Compact master ON / OFF','Advanced: choose your effects'],WHITE)]
 for i,(title,lines,color) in enumerate(cards):
  x=28+395*i
  out+=f'<rect x="{x}" y="25" width="354" height="200" rx="14" fill="#1d2328"/><rect x="{x+22}" y="49" width="42" height="5" rx="2" fill="{color}"/>'
  out+=f'<text x="{x+22}" y="96" font-family="Segoe UI,Arial,sans-serif" font-size="18" font-weight="800" fill="{color}">{title}</text>'
  for j,line in enumerate(lines):out+=f'<text x="{x+22}" y="{139+j*32}" font-family="Segoe UI,Arial,sans-serif" font-size="17" fill="{WHITE}">{line}</text>'
 return out
if __name__=='__main__':
 p=ROOT/'docs/assets';p.mkdir(exist_ok=True)
 from brand_kit import build,BANNER
 (p/'acng-banner.svg').write_text(build()[BANNER])
 (p/'acng-overview.svg').write_text(svg(1200,250,'ACNG feature overview - original illustration',overview()))
 print('Original README banner and feature overview generated.')
