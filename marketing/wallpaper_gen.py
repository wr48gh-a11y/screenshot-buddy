#!/usr/bin/env python3
"""Generate an original macOS-style abstract wallpaper for marketing screenshots.

COMPOSITION RULES (these are what make it read as a desktop rather than a poster):

1. The headline sits at left:78px, width 590px, vertically centred (see gen.py's `.head`),
   which in this 2560x1600 space is roughly x 150-1340, y 600-1000. That region is kept
   DARK. The previous version put its brightest violet bloom at x=420, directly underneath
   the headline, and `.head h1 em` is a #9b6dff->#d98aff gradient: same hue, similar
   lightness, so the words disappeared into the background. Colour now lives bottom-right,
   and a dedicated dark scrim (`make_text_scrim`) guarantees the contrast no matter how the
   glow is retuned.

2. Atmosphere is built from wide, heavily blurred RADIAL blooms, never from stroked paths.
   The old version drew 310px-wide bezier strokes and blurred them; a constant-width stroke
   still reads as a tube however much you blur it, which is what made the result look like a
   wireframe. Light has no constant width.

3. The app panel occupies roughly x 1630-2510, y 70-1220. Glow is kept below and around it
   so the panel edge stays crisp against a darker field.

The renderer is ImageMagick, which keeps the script self-contained even without Pillow or
NumPy in the environment.
"""

from __future__ import annotations

import pathlib
import shutil
import subprocess
import tempfile


WIDTH = 2560
HEIGHT = 1600

# Tuning knobs.
BASE_TOP = "#07060f"
BASE_BOTTOM = "#160f2b"
VIOLET = "#7B4DFF"
MAGENTA = "#B44DFF"
DEEP_BLUE = "#142b66"
EMBER = "#d7b7ff"

TOP_FADE_ALPHA = 0.84
TOP_RIGHT_ALPHA = 0.95
# How hard the headline area is protected. Raise if copy ever moves or grows.
TEXT_SCRIM_ALPHA = 0.62
# Grain does double duty: texture, and dithering away the banding that 8-bit gradients
# show across a field this large and this smooth.
GRAIN_STRENGTH = 0.022

OUT = pathlib.Path(__file__).with_name("assets") / "wallpaper.png"


def chromeless_magick() -> str:
    candidates = [shutil.which("magick"), shutil.which("convert")]
    for candidate in candidates:
        if candidate and pathlib.Path(candidate).exists():
            return candidate
    raise FileNotFoundError("Could not find an ImageMagick binary for rendering.")


def run_magick(*args: object) -> None:
    subprocess.run(
        [chromeless_magick(), *map(str, args)],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def rgba(hex_color: str, alpha: float) -> str:
    h = hex_color.lstrip("#")
    a = max(0, min(255, round(alpha * 255)))
    return f"#{h}{a:02X}"


def ellipse(cx: int, cy: int, rx: int, ry: int) -> str:
    return f"ellipse {cx},{cy} {rx},{ry} 0,360"


# Blurs this wide are the whole point of the look, but a sigma-300 gaussian across
# 2560x1600 takes minutes and still bands. Shrinking first, blurring in the small space,
# then scaling back up is both far faster and SMOOTHER: the upscale interpolates, which
# dithers away the terracing a full-resolution blur leaves behind.
BLUR_SCALE = 8


def soft(path: pathlib.Path, sigma: float, *draw_args: object) -> None:
    """Draw shapes at full size, then blur them via the shrink/grow trick."""
    small_w, small_h = WIDTH // BLUR_SCALE, HEIGHT // BLUR_SCALE
    run_magick(
        "-size", f"{WIDTH}x{HEIGHT}", "xc:none",
        *draw_args,
        "-resize", f"{small_w}x{small_h}!",
        "-blur", f"0x{sigma / BLUR_SCALE:.2f}",
        "-resize", f"{WIDTH}x{HEIGHT}!",
        path,
    )


def make_base(path: pathlib.Path) -> None:
    # A restrained top-to-bottom base gradient keeps the top strip dark enough for menu bar text.
    run_magick("-size", f"{WIDTH}x{HEIGHT}", f"gradient:{BASE_TOP}-{BASE_BOTTOM}", path)


def make_top_fade(path: pathlib.Path) -> None:
    soft(
        path, 80,
        "-fill", rgba("#04040b", TOP_FADE_ALPHA),
        "-draw", f"rectangle 0,0 {WIDTH},250",
    )


def make_top_right_shadow(path: pathlib.Path) -> None:
    soft(
        path, 150,
        "-fill", rgba("#03040a", TOP_RIGHT_ALPHA),
        "-draw", ellipse(2240, 210, 820, 560),
        "-fill", rgba("#04040b", 0.74),
        "-draw", ellipse(2460, 120, 560, 360),
    )


def make_glow(path: pathlib.Path) -> None:
    """The colour field: a low aurora sitting along the bottom-right.

    Every centre is at or below y=1400 and right of x=1050, so the light rises INTO frame
    from beneath rather than blooming behind the headline. Radii are deliberately enormous
    relative to the canvas; that plus the 300px blur is what separates 'atmosphere' from
    'a shape someone drew'.
    """
    soft(
        path, 300,
        # Main violet mass. Centre sits well below the frame so only its dim outer falloff
        # is visible: pushing the hot core off-canvas is what stops the bottom edge looking
        # like a bright strip that got cropped.
        "-fill", rgba(VIOLET, 0.68),
        "-draw", ellipse(1500, 1880, 1220, 700),
        # Three offset lobes at differing heights. A single ellipse gives a perfect arc,
        # which reads as geometry; overlapping lobes give the uneven crest real aurorae have.
        "-fill", rgba(VIOLET, 0.30),
        "-draw", ellipse(980, 1780, 700, 520),
        "-fill", rgba(MAGENTA, 0.34),
        "-draw", ellipse(1980, 1810, 820, 560),
        "-fill", rgba(MAGENTA, 0.22),
        "-draw", ellipse(2420, 1640, 620, 420),
        # A dimmer, higher band on the right, layered above the main mass so the glow has
        # depth rather than being one wall of light.
        "-fill", rgba(MAGENTA, 0.16),
        "-draw", ellipse(2020, 1320, 700, 300),
        # Cool counterweight so the field is not a single flat hue.
        "-fill", rgba(DEEP_BLUE, 0.40),
        "-draw", ellipse(1150, 1520, 780, 460),
        "-fill", rgba(DEEP_BLUE, 0.24),
        "-draw", ellipse(1720, 1400, 560, 300),
        # Small bright core, keeps the aurora from reading as uniform haze.
        "-fill", rgba(EMBER, 0.12),
        "-draw", ellipse(1700, 1700, 420, 240),
    )


def make_far_accent(path: pathlib.Path) -> None:
    """A whisper of violet in the upper left.

    Without this the left half is dead flat once the scrim lands. Alpha is kept very low:
    it is there to stop the corner reading as empty, not to be noticed.
    """
    soft(
        path, 320,
        # Upper-left violet. Enough to keep the corner alive under the scrim, not enough to
        # compete with the headline that sits just below it.
        "-fill", rgba(VIOLET, 0.26),
        "-draw", ellipse(180, 300, 900, 620),
        "-fill", rgba(DEEP_BLUE, 0.30),
        "-draw", ellipse(20, 820, 640, 620),
        # A cool wash down the left edge so the darkest region still has hue in it. Pure
        # black next to a saturated aurora reads as a hole in the image, not as depth.
        "-fill", rgba(DEEP_BLUE, 0.20),
        "-draw", ellipse(120, 1400, 700, 520),
        # Faint counter-light top-right, above the panel, to balance the bottom-heavy glow.
        "-fill", rgba(MAGENTA, 0.10),
        "-draw", ellipse(2400, 60, 700, 420),
    )


def make_text_scrim(path: pathlib.Path) -> None:
    """Darken the headline zone so the violet `em` gradient always has somewhere to sit.

    Composited `over` (not `screen`) precisely so it can subtract light the glow added.
    This is the guarantee: retune the aurora however you like, the copy stays legible.
    """
    soft(
        path, 260,
        "-fill", rgba("#050410", TEXT_SCRIM_ALPHA),
        "-draw", ellipse(600, 800, 980, 660),
        "-fill", rgba("#050410", 0.34),
        "-draw", ellipse(980, 900, 700, 520),
    )


def composite(base: pathlib.Path, overlay: pathlib.Path, out: pathlib.Path, mode: str = "over") -> None:
    run_magick(base, overlay, "-compose", mode, "-composite", out)


def render() -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="wallpaper_gen_") as tmp:
        tmp = pathlib.Path(tmp)
        base = tmp / "base.png"
        glow = tmp / "glow.png"
        far_accent = tmp / "far_accent.png"
        scrim = tmp / "scrim.png"
        top_fade = tmp / "top_fade.png"
        top_right = tmp / "top_right.png"
        stage = [tmp / f"stage{i}.png" for i in range(1, 7)]

        make_base(base)
        make_glow(glow)
        make_far_accent(far_accent)
        make_text_scrim(scrim)
        make_top_fade(top_fade)
        make_top_right_shadow(top_right)

        # Light first, then subtract it back where the copy lives, then the menu bar chrome.
        composite(base, glow, stage[0], mode="screen")
        composite(stage[0], far_accent, stage[1], mode="screen")
        composite(stage[1], scrim, stage[2])
        composite(stage[2], top_fade, stage[3])
        composite(stage[3], top_right, stage[4])
        run_magick(stage[4], "-attenuate", str(GRAIN_STRENGTH), "+noise", "Gaussian", OUT)


def main() -> None:
    render()


if __name__ == "__main__":
    main()
