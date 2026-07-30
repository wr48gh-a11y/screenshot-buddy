#!/usr/bin/env python3
"""Render the desktop wallpaper behind the App Store marketing shots.

Original artwork, generated procedurally — nothing traced from or derived from Apple's
wallpapers. Composed as a stack of soft radial blooms over a near-black violet base, so
there are no hard stops anywhere; a single gradient with an abrupt stop reads as a seam
across the image and instantly kills the illusion of a photographed desktop.

The composition is driven entirely by what sits on top of it in gen.py:
  - The menu bar runs across the very top, so the top strip stays near-black for contrast.
  - The panel hangs off the top-right, so that corner is darkened hard and kept empty.
  - The headline sits mid-left over the background, so the left side stays dark enough for
    white type to hold. The brightest bloom is pushed BELOW it, into the bottom edge, where
    nothing overlaps.

Renders through headless Chrome, matching gen.py — neither Pillow nor numpy is installed
here, and CSS gradients composite without banding for free.

Output: assets/wallpaper.png at 2560x1600 (1280x800 logical @2x).
"""
import subprocess, pathlib

OUT = pathlib.Path(__file__).parent
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

BASE = "#100d1e"        # near-black violet the whole image sits on
GLOW = "123,77,255"     # #7B4DFF — the app's signature violet
LIFT = "180,77,255"     # #B44DFF — its lighter partner, used sparingly

# Ordered front to back, the way CSS composites multiple backgrounds. Every layer fades to
# transparent well inside its own bounds so nothing ever meets an edge abruptly.
LAYERS = [
    # Darkening passes, listed first so they sit ON TOP of the color.
    "linear-gradient(180deg, rgba(4,3,10,.92) 0%, rgba(4,3,10,.55) 9%, rgba(4,3,10,0) 26%)",
    "radial-gradient(ellipse 62% 78% at 101% -8%, rgba(4,3,10,.82) 0%, rgba(4,3,10,.35) 45%, rgba(4,3,10,0) 72%)",
    "radial-gradient(ellipse 85% 60% at 50% 46%, rgba(4,3,10,.30) 0%, rgba(4,3,10,0) 68%)",
    # Light. The big bloom is low and left; a smaller one balances it centre-right.
    f"radial-gradient(ellipse 62% 52% at 16% 104%, rgba({GLOW},.62) 0%, rgba({GLOW},.22) 42%, rgba({GLOW},0) 72%)",
    f"radial-gradient(ellipse 46% 34% at 62% 116%, rgba({LIFT},.42) 0%, rgba({LIFT},0) 70%)",
    "radial-gradient(ellipse 34% 46% at -6% 62%, rgba(96,64,210,.38) 0%, rgba(96,64,210,0) 70%)",
    f"radial-gradient(ellipse 40% 26% at 84% 88%, rgba({GLOW},.20) 0%, rgba({GLOW},0) 72%)",
    # A faint cool cast up top keeps the dark half from going flat grey.
    "radial-gradient(ellipse 70% 40% at 34% 8%, rgba(58,44,132,.30) 0%, rgba(58,44,132,0) 70%)",
    BASE,
]

# Two blurred ribbons give the flow that pure radials can't — without them the result reads
# as a vignette rather than a wallpaper. Blurred far past their own size so no edge survives.
RIBBONS = """
.ribbon { position:absolute; border-radius:50%; filter:blur(90px); mix-blend-mode:screen; }
.r1 { left:-14%; top:58%; width:86%; height:30%; background:rgba(123,77,255,.34); transform:rotate(-13deg); }
.r2 { left:26%;  top:80%; width:70%; height:24%; background:rgba(180,77,255,.22); transform:rotate(-6deg); }
.r3 { left:-8%;  top:34%; width:44%; height:16%; background:rgba(96,64,210,.20); transform:rotate(-18deg); }
"""

# feTurbulence grain. Large flat gradients band visibly on a retina panel; a couple of
# percent of noise breaks the bands up without reading as texture.
GRAIN = """<svg class="grain" xmlns="http://www.w3.org/2000/svg">
  <filter id="n"><feTurbulence type="fractalNoise" baseFrequency="0.8" numOctaves="3" stitchTiles="stitch"/>
  <feColorMatrix type="saturate" values="0"/></filter>
  <rect width="100%" height="100%" filter="url(#n)"/></svg>"""

HTML = f"""<!DOCTYPE html><html><head><meta charset='utf-8'><style>
* {{ margin:0; padding:0; }}
html,body {{ width:1280px; height:800px; overflow:hidden; }}
body {{ position:relative; background:{', '.join(LAYERS)}; }}
{RIBBONS}
.grain {{ position:absolute; inset:0; width:100%; height:100%; opacity:.035; pointer-events:none; }}
</style></head><body>
<div class="ribbon r3"></div><div class="ribbon r1"></div><div class="ribbon r2"></div>
{GRAIN}
</body></html>"""

if __name__ == "__main__":
    (OUT / "assets").mkdir(exist_ok=True)
    hp = OUT / "_wallpaper.html"
    hp.write_text(HTML)
    png = OUT / "assets" / "wallpaper.png"
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                    "--force-device-scale-factor=2", "--window-size=1280,800",
                    f"--screenshot={png}", str(hp)],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    hp.unlink()
    print(f"rendered {png}")
