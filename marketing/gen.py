#!/usr/bin/env python3
"""Generate App Store marketing screenshots (1280x800 logical, rendered @2x = 2560x1600)."""
import os, base64, subprocess, pathlib

OUT = pathlib.Path(__file__).parent
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

SPIRAL = 'M498 468 L618 468 L618 601 L418 614 L405 368 L738 355 L765 701 L318 734 L285 268'

CSS = """
* { margin:0; padding:0; box-sizing:border-box; }
html,body { width:1280px; height:800px; overflow:hidden; }
body { font-family:-apple-system,BlinkMacSystemFont,"SF Pro Display",Helvetica,sans-serif;
  position:relative; background:__BG__; background-size:cover; background-position:center; }
/* macOS menu bar. The whole point of these shots is that the panel HANGS OFF this strip —
   without it the panel reads as a floating poster card, not a menu bar app. */
.menubar { position:absolute; top:0; left:0; right:0; height:26px; z-index:6;
  display:flex; align-items:center; padding:0 14px; gap:19px;
  background:rgba(16,12,30,.5); backdrop-filter:blur(24px);
  border-bottom:1px solid rgba(255,255,255,.07);
  font-size:13px; font-weight:450; color:rgba(255,255,255,.92); }
.menubar .app { font-weight:700; }
.menubar .right { margin-left:auto; display:flex; align-items:center; gap:15px; }
.menubar .right svg { width:15px; height:15px; fill:rgba(255,255,255,.9); }
.menubar .clock { font-variant-numeric:tabular-nums; }
/* The app's own menu bar item, drawn in the pressed state macOS gives an open extra. */
.mb-app { display:flex; align-items:center; padding:4px 8px; border-radius:5px;
  background:rgba(255,255,255,.24); }
.mb-app svg { width:15px; height:15px; }
/* Everything below the menu bar. Headline left, panel hanging top-right where a menu bar
   extra actually opens — never centered. */
.stage { position:absolute; top:26px; left:0; right:0; bottom:0; }
.head { position:absolute; left:78px; top:50%; transform:translateY(-50%); width:590px; z-index:2; }
.head h1 { font-size:50px; font-weight:800; letter-spacing:-1px; color:#fff; line-height:1.08; }
.head h1 em { font-style:normal; background:linear-gradient(90deg,#9b6dff,#d98aff); -webkit-background-clip:text; background-clip:text; color:transparent; }
.head p { font-size:21px; color:#c4b9ee; margin-top:16px; font-weight:400; line-height:1.4; }
/* app panel */
.anchor { position:absolute; top:11px; right:40px; z-index:3; }
/* Ties the panel to the menu bar icon above it. right: is tuned so the point lands under
   .mb-app — if you reorder the menu bar status items, retune it. */
.notch { position:absolute; top:-8px; right:150px; width:20px; height:9px; background:#2b2049;
  clip-path:polygon(50% 0, 100% 100%, 0 100%); }
.panel { width:430px; background:linear-gradient(180deg,#241a3d,#181026); border-radius:22px;
  box-shadow:0 40px 100px rgba(0,0,0,.55), 0 0 0 1px rgba(255,255,255,.06); overflow:hidden; }
/* Sits on the menu bar icon: reads as "you just clicked this and the panel dropped down." */
.cursor { position:absolute; top:16px; right:188px; width:19px; height:19px; z-index:7;
  filter:drop-shadow(0 1px 2px rgba(0,0,0,.5)); }
.p-head { display:flex; align-items:center; gap:13px; padding:16px 18px; }
.ring { width:48px; height:48px; border-radius:50%; position:relative; flex-shrink:0;
  background:conic-gradient(#7b4dff 0 55%, rgba(255,255,255,.12) 55% 100%); display:flex; align-items:center; justify-content:center; }
.ring::after { content:""; position:absolute; inset:5px; border-radius:50%; background:#1d1533; }
.ring span { position:relative; z-index:2; color:#fff; font-weight:700; font-size:16px; }
.p-head .t b { display:block; color:#fff; font-size:16px; font-weight:650; }
.p-head .t small { color:#a79bd8; font-size:12.5px; }
.p-head .icons { margin-left:auto; display:flex; gap:12px; color:#a79bd8; font-size:15px; }
.divider { height:1px; background:rgba(255,255,255,.07); }
.grid { display:grid; grid-template-columns:1fr 1fr; gap:10px; padding:14px; }
.cell { display:flex; flex-direction:column; gap:5px; }
.thumb { height:104px; border-radius:9px; box-shadow:0 3px 10px rgba(0,0,0,.35); position:relative; overflow:hidden;
  background-size:cover; background-position:top center; }
.thumb.sel { outline:3px solid #8f6cff; }
.thumb .ph { position:absolute; inset:0; display:flex; align-items:center; justify-content:center; }
.thumb .ph svg { width:26px; height:26px; opacity:.5; }
.cell small { font-size:11.5px; color:#a79bd8; padding-left:2px; }
.foot { margin:8px 14px 16px; display:flex; gap:10px; }
.sweep { flex:1.6; display:flex; align-items:center; gap:9px; height:52px; border-radius:26px;
  background:linear-gradient(90deg,#7b4dff,#b44dff); box-shadow:0 8px 26px rgba(123,77,255,.5); color:#fff; padding:0 18px; }
.sweep .mk { width:19px; height:19px; }
.sweep b { font-size:15px; font-weight:650; white-space:nowrap; }
.sweep .chip { margin-left:auto; font-size:12.5px; font-weight:650; background:rgba(255,255,255,.2); border-radius:20px; padding:5px 11px; }
.danger { flex:1; display:flex; align-items:center; justify-content:center; height:52px; border-radius:26px;
  background:rgba(226,72,72,.16); border:1px solid rgba(226,72,72,.55); color:#ff9c93; font-size:13.5px; font-weight:650; white-space:nowrap; }
/* welcome variant — a real floating window, so this one stays centered on the desktop */
.welcome { position:absolute; inset:0; display:flex; flex-direction:column;
  align-items:center; justify-content:center; text-align:center; }
.welcome .mark { width:96px; height:96px; margin:0 auto 26px; filter:drop-shadow(0 0 28px rgba(123,77,255,.55)); }
.welcome h2 { font-size:34px; font-weight:800; color:#fff; }
.welcome h2 em { font-style:normal; color:#c9a2ff; }
.welcome p { font-size:17px; color:#b9aee6; margin-top:14px; }
.welcome .btn { display:inline-block; margin-top:30px; padding:14px 34px; border-radius:30px; font-size:16px; font-weight:650; color:#fff;
  background:linear-gradient(90deg,#7b4dff,#b44dff); box-shadow:0 8px 26px rgba(123,77,255,.5); }
.badge-row { position:absolute; bottom:40px; left:0; right:0; display:flex; justify-content:center; gap:10px; z-index:2; }
.badge-row .b { font-size:14px; color:#c9b8ff; border:1px solid rgba(160,120,255,.35); border-radius:20px; padding:8px 16px; }
"""

# Mock screenshots rendered by thumbsrc.py, inlined so the slide HTML stays self-contained
# (headless Chrome loads it from a temp path where relative file refs don't resolve).
THUMB_SRC = sorted((OUT / "thumbsrc").glob("*.png"))
THUMB_URIS = ["data:image/png;base64," + base64.b64encode(p.read_bytes()).decode()
              for p in THUMB_SRC]

def thumbs(sel_index=-1, n=6, times=None):
    times = times or ["2m ago","8m ago","1h ago","3h ago","Yesterday","2d ago"]
    out=""
    for i in range(n):
        sel=" sel" if i==sel_index else ""
        uri=THUMB_URIS[i%len(THUMB_URIS)]
        out+=f'''<div class="cell"><div class="thumb{sel}" style="background-image:url({uri})"></div>
        <small>{times[i]}</small></div>'''
    return out

def mark(stroke="#fff", width=46):
    return f'<svg viewBox="260 242 528 518"><path fill="none" stroke="{stroke}" stroke-width="{width}" ' \
           f'stroke-linecap="round" stroke-linejoin="round" d="{SPIRAL}"/></svg>'

# Generic glyphs, deliberately not traced from Apple's. They only need to read as "status
# icons" at a glance; nobody inspects them, and copying Apple's art is a rejection risk.
WIFI = '<svg viewBox="0 0 16 16"><path d="M8 12.6a1.2 1.2 0 110 2.4 1.2 1.2 0 010-2.4zM8 8.4c1.5 0 2.9.6 3.9 1.6l-1.3 1.3A3.7 3.7 0 008 10.2c-1 0-2 .4-2.6 1.1L4.1 10A5.5 5.5 0 018 8.4zm0-4.2c2.7 0 5.1 1.1 6.9 2.8l-1.3 1.3A8 8 0 008 6.1a8 8 0 00-5.6 2.2L1.1 7A9.7 9.7 0 018 4.2z"/></svg>'
BATT = '<svg viewBox="0 0 24 16"><rect x="1" y="3" width="18" height="10" rx="3" fill="none" stroke="rgba(255,255,255,.85)" stroke-width="1.4"/><rect x="3" y="5" width="12" height="6" rx="1.6"/><path d="M20.6 6.2v3.6a2.2 2.2 0 000-3.6z"/></svg>'
SEARCH = '<svg viewBox="0 0 16 16"><path d="M7 1.6a5.4 5.4 0 014.3 8.7l3.2 3.2-1.1 1.1-3.2-3.2A5.4 5.4 0 117 1.6zm0 1.6a3.8 3.8 0 100 7.6 3.8 3.8 0 000-7.6z"/></svg>'
CURSOR = '<svg class="cursor" viewBox="0 0 12 19"><path d="M1 1l10 9.6H6.2l2.5 5.9-2.2.9-2.5-5.9L1 15.1z" fill="#fff" stroke="#1a1a1a" stroke-width="1"/></svg>'

# Screenshot Buddy is LSUIElement — it has no app menus and never owns the menu bar. Whatever
# the user was actually in stays frontmost, so show Finder rather than claiming menus we
# don't have.
MENUBAR = f'''<div class="menubar">
    <span class="app">Finder</span><span>File</span><span>Edit</span><span>View</span><span>Go</span><span>Window</span><span>Help</span>
    <div class="right">
      <span class="mb-app">{mark(width=64)}</span>
      {WIFI}{BATT}{SEARCH}
      <span class="clock">Thu 10:24</span>
    </div>
  </div>{CURSOR}'''


def panel(sel=-1, sweep_size="2.7 MB", count=6):
    return f'''<div class="anchor"><div class="notch"></div><div class="panel">
      <div class="p-head">
        <div class="ring"><span>{count}</span></div>
        <div class="t"><b>Desktop</b><small>{count} files</small></div>
        <div class="icons">📁 &nbsp;⚙</div>
      </div>
      <div class="divider"></div>
      <div class="grid">{thumbs(sel, count)}</div>
      <div class="divider"></div>
      <div class="foot">
        <div class="sweep"><svg class="mk" viewBox="260 242 528 518"><path fill="none" stroke="#fff" stroke-width="46" stroke-linecap="round" stroke-linejoin="round" d="{SPIRAL}"/></svg><b>Sweep to Trash</b><span class="chip">{sweep_size}</span></div>
        <div class="danger">Delete Forever</div>
      </div>
    </div></div>'''

SLIDES = {
  "01-hero": f'''<div class="head"><h1>Your screenshots,<br><em>one click away.</em></h1><p>Every shot in your menu bar. No more digging through Finder.</p></div>{panel(sel=0)}''',
  "02-sweep": f'''<div class="head"><h1>Sweep it <em>all away.</em></h1><p>Clear the whole folder in one click, and see the space you got back.</p></div>{panel(sweep_size="48 MB", count=6)}''',
  "03-manage": f'''<div class="head"><h1>Preview, drag, <em>rename.</em></h1><p>Press Space to Quick Look. Drag straight into any app. Rename in place.</p></div>{panel(sel=2)}''',
  "04-private": f'''<div class="welcome">
      <svg class="mark" viewBox="260 242 528 518"><path fill="none" stroke="url(#g)" stroke-width="46" stroke-linecap="round" stroke-linejoin="round" d="{SPIRAL}"/><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#9b6dff"/><stop offset="1" stop-color="#d98aff"/></linearGradient></defs></svg>
      <h2>Private by <em>design.</em></h2>
      <p>No account. No tracking. Nothing ever leaves your Mac.</p>
      <div class="btn">Connect Your Screenshots Folder</div>
    </div>
    <div class="badge-row"><span class="b">Menu bar app</span><span class="b">Collects no data</span><span class="b">Made for macOS</span></div>''',
}

# Desktop wallpaper. Falls back to the old flat gradient so the script still runs standalone,
# but a real wallpaper is what sells "this is floating over my desktop" rather than "poster".
WALL = OUT / "assets" / "wallpaper.png"
BG = ("url(data:image/png;base64," + base64.b64encode(WALL.read_bytes()).decode() + ")"
      if WALL.exists() else
      "radial-gradient(ellipse 90% 70% at 50% 116%, #3a2578 0%, #241a4d 44%, #100a22 100%)")
CSS = CSS.replace("__BG__", BG)

for name, body in SLIDES.items():
    html = (f"<!DOCTYPE html><html><head><meta charset='utf-8'><style>{CSS}</style></head>"
            f"<body>{MENUBAR}<div class='stage'>{body}</div></body></html>")
    hp = OUT / f"{name}.html"
    hp.write_text(html)
    png = OUT / f"{name}.png"
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                    "--force-device-scale-factor=2", "--window-size=1280,800",
                    f"--screenshot={png}", str(hp)],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print("rendered", png.name)
