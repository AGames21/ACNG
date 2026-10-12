# ACNG brand kit: Track teal

Original artwork for the README, videos and thumbnails. Every file here is made by
`python tools/brand_kit.py` (add `--png` to also render PNGs with a local Chrome or Edge).
Do not edit the SVGs by hand. Change the generator and rerun it. `tests/test_brand_kit.py`
fails when a committed file no longer matches the generator.

## Colours

| Name   | Hex       | Use |
| ------ | --------- | --- |
| Carbon | `#121417` | Backgrounds and panels |
| Teal   | `#00D1B2` | The mark, rules, stripes and one highlighted word |
| White  | `#F4F6F5` | Text |
| Amber  | `#FFB020` | Small highlights only (BETA tag, warnings) |

The HUD tire colours (blue cold, green ideal, red hot) are data colours and stay separate
from the brand.

## Mark and type

The mark is three slanted teal bars, one each for the inner, middle and outer tread zones
of the tire model. The wordmark is "ACNG" in heavy italic (Segoe UI Black, falling back to
Arial Black). The body text uses Segoe UI or Arial.

## Files

| File | Size | Use |
| ---- | ---- | --- |
| `acng-logo.svg` / `.png` | 1080x300 | Logo on dark backgrounds |
| `acng-logo-light.svg` / `.png` | 1080x300 | Logo on light backgrounds |
| `acng-icon.svg` / `.png` | 512x512 | Avatar or channel icon |
| `acng-title-card.svg` / `.png` | 1920x1080 | Video intro and outro card |
| `acng-lower-third.svg` / `.png` | 1920x1080, transparent | Feature caption overlay. Change the text in `lower_third()` |
| `acng-thumbnail.svg` / `.png` | 1280x720 | YouTube thumbnail template. Put a car shot on the grey area |
| `../assets/acng-banner.svg` | 1200x460 | README banner |

## Rules

- Label public videos "unofficial mod". The title card and banner already carry the
  disclaimer.
- Use no BeamNG or Assetto Corsa logos and no game music.
- Show only stock BeamNG cars and maps in public footage, unless the maintainer approves
  something else.

## Video

1. Film a lab experiment with `python tools/film_lab.py --experiment <Name>`. It runs in a
   fresh lab profile with only the ACNG HUD and cuts clips between the harness's film cues.
2. Cut a short with `python tools/cut_short.py tools/shorts/tires-v1.json --clip
   name=<clip.mp4> ... --out <work>/<name>.mp4`. The plan lists title cards and clip
   segments (start, end, speed, lower-third text, HUD inset). Each clip segment gets the
   brand lower third, an "UNOFFICIAL MOD · BETA · STOCK CAR, LAB TEST" label, its speed,
   and a 3x zoom of the tire tiles.

The output is silent; the maintainer picks the music. Video stays outside the repository.
