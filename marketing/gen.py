#!/usr/bin/env python3
"""Generate App Store marketing screenshots (1280x800 logical, rendered @2x = 2560x1600)."""
import os, subprocess, pathlib

OUT = pathlib.Path(__file__).parent
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

SPIRAL = 'M498 468 L618 468 L618 601 L418 614 L405 368 L738 355 L765 701 L318 734 L285 268'

CSS = """
* { margin:0; padding:0; box-sizing:border-box; }
html,body { width:1280px; height:800px; overflow:hidden; }
body { font-family:-apple-system,BlinkMacSystemFont,"SF Pro Display",Helvetica,sans-serif;
  display:flex; flex-direction:column; align-items:center; justify-content:center;
  background:radial-gradient(ellipse 90% 70% at 50% 116%, #3a2578 0%, #241a4d 44%, #100a22 100%); position:relative; }
.head { text-align:center; margin-bottom:40px; z-index:2; }
.head h1 { font-size:52px; font-weight:800; letter-spacing:-1px; color:#fff; line-height:1.08; }
.head h1 em { font-style:normal; background:linear-gradient(90deg,#9b6dff,#d98aff); -webkit-background-clip:text; background-clip:text; color:transparent; }
.head p { font-size:22px; color:#b9aee6; margin-top:16px; font-weight:400; }
/* app panel */
.panel { width:430px; background:linear-gradient(180deg,#241a3d,#181026); border-radius:22px;
  box-shadow:0 40px 100px rgba(0,0,0,.55), 0 0 0 1px rgba(255,255,255,.06); overflow:hidden; z-index:2; }
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
.thumb { height:104px; border-radius:9px; box-shadow:0 3px 10px rgba(0,0,0,.35); position:relative; overflow:hidden; }
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
/* welcome variant */
.welcome { text-align:center; }
.welcome .mark { width:96px; height:96px; margin:0 auto 26px; filter:drop-shadow(0 0 28px rgba(123,77,255,.55)); }
.welcome h2 { font-size:34px; font-weight:800; color:#fff; }
.welcome h2 em { font-style:normal; color:#c9a2ff; }
.welcome p { font-size:17px; color:#b9aee6; margin-top:14px; }
.welcome .btn { display:inline-block; margin-top:30px; padding:14px 34px; border-radius:30px; font-size:16px; font-weight:650; color:#fff;
  background:linear-gradient(90deg,#7b4dff,#b44dff); box-shadow:0 8px 26px rgba(123,77,255,.5); }
.badge-row { position:absolute; bottom:40px; display:flex; gap:10px; z-index:2; }
.badge-row .b { font-size:14px; color:#c9b8ff; border:1px solid rgba(160,120,255,.35); border-radius:20px; padding:8px 16px; }
"""

def thumbs(sel_index=-1, n=6, times=None):
    times = times or ["2m ago","8m ago","1h ago","3h ago","Yesterday","2d ago"]
    tones = ["#3a4a6b,#2c3a55","#4a3a6b,#352c55","#3a5a5b,#2c4a45","#5b4a3a,#453c2c","#3a4a6b,#2c3a55","#4a3a6b,#352c55"]
    out=""
    for i in range(n):
        g=tones[i%len(tones)]; sel=" sel" if i==sel_index else ""
        out+=f'''<div class="cell"><div class="thumb{sel}" style="background:linear-gradient(135deg,{g})">
        <div class="ph"><svg viewBox="0 0 24 24" fill="#fff"><path d="M4 5h16v12H4z" opacity=".3"/><circle cx="9" cy="10" r="2" fill="#fff"/><path d="M4 17l5-5 4 3 3-2 4 4z" fill="#fff"/></svg></div></div>
        <small>{times[i]}</small></div>'''
    return out

def panel(sel=-1, sweep_size="2.7 MB", count=6):
    return f'''<div class="panel">
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
    </div>'''

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

for name, body in SLIDES.items():
    html = f"<!DOCTYPE html><html><head><meta charset='utf-8'><style>{CSS}</style></head><body>{body}</body></html>"
    hp = OUT / f"{name}.html"
    hp.write_text(html)
    png = OUT / f"{name}.png"
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                    "--force-device-scale-factor=2", "--window-size=1280,800",
                    f"--screenshot={png}", str(hp)],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print("rendered", png.name)
