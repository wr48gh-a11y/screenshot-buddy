#!/usr/bin/env python3
"""Render the six thumbnail images that fill the grid in the marketing shots.

The panel grid used to draw flat gradients with a generic image glyph, which reads as
"placeholder" the moment anyone looks at it. These are mock screenshots of the things the
target user actually captures all day — terminal output, a diff, a failing test, a browser —
so the product page shows the app doing its job instead of an empty frame.

Output: thumbsrc/*.png, consumed by gen.py and inlined as data URIs.
"""
import shutil, subprocess, pathlib

OUT = pathlib.Path(__file__).parent / "thumbsrc"
OUT.mkdir(exist_ok=True)
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

W, H = 640, 400

BASE = """
* { margin:0; padding:0; box-sizing:border-box; }
html,body { width:640px; height:400px; overflow:hidden;
  font:13px/1.55 ui-monospace,'SF Mono',Menlo,monospace; }
.win { width:640px; height:400px; display:flex; flex-direction:column; }
.bar { height:34px; flex:none; display:flex; align-items:center; gap:8px; padding:0 13px; }
.bar i { width:11px; height:11px; border-radius:50%; display:block; }
.bar .t { font:600 12px -apple-system,'SF Pro Text',sans-serif; margin-left:8px; opacity:.62; }
.body { flex:1; padding:15px 18px; overflow:hidden; }
.body div { white-space:pre; }
"""

# Dark chrome shared by the terminal/editor mocks; light chrome for the browser one.
DARK = """
.win { background:#1b1d24; }
.bar { background:#25272f; border-bottom:1px solid #14161c; }
.bar .t { color:#cfd3e0; }
.body { color:#c8ccd8; }
"""
LIGHT = """
.win { background:#fff; }
.bar { background:#eceef2; border-bottom:1px solid #d8dbe2; }
.bar .t { color:#3c4150; }
.body { color:#333; font:14px/1.6 -apple-system,'SF Pro Text',sans-serif; }
"""

DOTS = '<i style="background:#ff5f57"></i><i style="background:#febc2e"></i><i style="background:#28c840"></i>'


def win(title, body, chrome=DARK, extra=""):
    return f"<style>{BASE}{chrome}{extra}</style>" \
           f'<div class="win"><div class="bar">{DOTS}<span class="t">{title}</span></div>' \
           f'<div class="body">{body}</div></div>'


# 1. A failing test run — the single most-screenshotted thing in an agent loop.
TESTS = win("zsh — pytest", """<div><span style="color:#7ee787">➜</span>  <span style="color:#79c0ff">api</span> pytest -q</div>
<div style="color:#6e7681">collected 48 items</div>
<div style="color:#7ee787">........................................<span style="color:#ff7b72">F</span>.......</div>
<div>&nbsp;</div>
<div style="color:#ff7b72">FAILED tests/test_auth.py::test_expired_token</div>
<div style="color:#8b949e">  assert response.status_code == 401</div>
<div style="color:#8b949e">E   assert 500 == 401</div>
<div>&nbsp;</div>
<div><span style="color:#ff7b72">1 failed</span>, <span style="color:#7ee787">47 passed</span> in 2.41s</div>""")

# 2. A diff — the second thing you paste back into the agent.
DIFF = win("session.py — Cursor", """<div style="color:#6e7681">@@ -14,7 +14,9 @@ def refresh(token):</div>
<div style="color:#8b949e">     claims = decode(token)</div>
<div style="background:#3a1d20;color:#ff9492">-    if claims.exp &lt; now():</div>
<div style="background:#3a1d20;color:#ff9492">-        return None</div>
<div style="background:#12261e;color:#7ee787">+    if claims.exp &lt; now():</div>
<div style="background:#12261e;color:#7ee787">+        raise TokenExpired(claims.sub)</div>
<div style="background:#12261e;color:#7ee787">+</div>
<div style="color:#8b949e">     return issue(claims.sub)</div>
<div>&nbsp;</div>
<div style="color:#6e7681">2 files changed, 9 insertions(+), 4 deletions(-)</div>""")

# Slots 3-6 are not generated here — they are static images in assets/, copied into place
# below. Rich GUI mockups (a chat client, a social feed, an error dialog) are more art than
# markup, and the grid needs that visual break from the wall of monospace. Any PNG dropped in
# assets/ claims the slot its filename prefix names; gen.py orders the grid by that prefix.

SHOTS = {"1-tests": TESTS, "2-diff": DIFF}

for src in sorted((pathlib.Path(__file__).parent / "assets").glob("*.png")):
    shutil.copyfile(src, OUT / src.name)
    print(f"✓ {src.name} (from assets/)")

for name, body in SHOTS.items():
    hp = OUT / f"{name}.html"
    hp.write_text(f"<!DOCTYPE html><html><head><meta charset='utf-8'></head><body>{body}</body></html>")
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                    "--force-device-scale-factor=2", f"--window-size={W},{H}",
                    f"--screenshot={OUT / f'{name}.png'}", str(hp)],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    hp.unlink()
    print(f"✓ {name}.png")
