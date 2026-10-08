#!/usr/bin/env python3
"""Build branding/kit from branding/logo-source.png.

The source wordmark is split into a TV mask and a MAESTRO mask by fitting
each pixel to the line from white to the template blue (#2764AF) or to the
template charcoal (#222931). Antialiased edges stay in the alpha channel.
ImageMagick writes the resized PNGs. SVG masters are traced with the
pure-Python potrace package (install name: potracer).

    pip install potracer
    python3 scripts/generate-logos.py
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "branding" / "logo-source.png"
KIT = ROOT / "branding" / "kit"

BLUE = (0x27, 0x64, 0xAF)
CHARCOAL = (0x22, 0x29, 0x31)
OFFWHITE = (0xE8, 0xEE, 0xF6)
WHITE = (0xFF, 0xFF, 0xFF)
APP_BG = "0E1218"

# Solid letter colors measured from branding/logo-source.png.
WORDMARKS = (
    ("canonical", BLUE, CHARCOAL),
    ("on-dark", BLUE, OFFWHITE),
    ("mono-dark", CHARCOAL, CHARCOAL),
    ("mono-light", OFFWHITE, OFFWHITE),
    ("mono-white", WHITE, WHITE),
)
SVG_WORDMARKS = ("canonical", "on-dark", "mono-dark", "mono-light")
MARKS = (
    ("blue", BLUE),
    ("charcoal", CHARCOAL),
    ("white", WHITE),
)

WORDMARK_HEIGHTS = (32, 48, 64, 128, 256)
MARK_SIZES = (16, 32, 180, 192, 512, 1024)
# Matches the content box of branding/logo-app-icon-512.png (317px on 512).
MARK_WIDTH_RATIO = 317 / 512
# Matches the content box of branding/logo-banner-640x360.png (560px on 640).
BANNER_WIDTH_RATIO = 560 / 640
TRACE_SCALE = 4

Rgb = tuple[int, int, int]


def magick(args: list[str], data: bytes | None = None, capture: bool = False) -> bytes:
    result = subprocess.run(
        ["magick", *args],
        input=data,
        check=True,
        stdout=subprocess.PIPE if capture else None,
    )
    return result.stdout if capture else b""


def read_rgba(path: Path) -> tuple[int, int, bytes]:
    info = subprocess.check_output(
        ["magick", str(path), "-format", "%w %h", "info:"],
        text=True,
    ).split()
    width, height = int(info[0]), int(info[1])
    raw = magick([str(path), "-depth", "8", "rgba:-"], capture=True)
    expected = width * height * 4
    if len(raw) != expected:
        raise RuntimeError(f"{path} decoded to {len(raw)} bytes, expected {expected}")
    return width, height, raw


def write_rgba(path: Path, width: int, height: int, rgba: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    magick(
        [
            "-size",
            f"{width}x{height}",
            "-depth",
            "8",
            "rgba:-",
            "-alpha",
            "set",
            f"PNG32:{path}",
        ],
        data=rgba,
    )


def _coverage(r: int, g: int, b: int, ink: Rgb) -> tuple[float, float]:
    vr = ink[0] - 255
    vg = ink[1] - 255
    vb = ink[2] - 255
    denom = vr * vr + vg * vg + vb * vb
    alpha = ((r - 255) * vr + (g - 255) * vg + (b - 255) * vb) / denom
    if alpha < 0:
        alpha = 0.0
    elif alpha > 1:
        alpha = 1.0
    err = (
        (r - (255 + alpha * vr)) ** 2
        + (g - (255 + alpha * vg)) ** 2
        + (b - (255 + alpha * vb)) ** 2
    )
    return alpha, err


def split_masks(width: int, height: int, rgba: bytes) -> tuple[bytearray, bytearray]:
    """Return TV and MAESTRO alpha masks. Antialiasing stays as partial alpha."""
    tv = bytearray(width * height)
    maestro = bytearray(width * height)
    for index in range(width * height):
        offset = index * 4
        r = rgba[offset]
        g = rgba[offset + 1]
        b = rgba[offset + 2]
        if r > 252 and g > 252 and b > 252:
            continue
        blue_a, blue_err = _coverage(r, g, b, BLUE)
        ink_a, ink_err = _coverage(r, g, b, CHARCOAL)
        if blue_err <= ink_err:
            alpha, err = blue_a, blue_err
            target = tv
        else:
            alpha, err = ink_a, ink_err
            target = maestro
        # Pixels that are not a blend of white and either ink are background.
        if err > 2500 or alpha < 1 / 255:
            continue
        target[index] = int(round(alpha * 255))
    # The white field has a faint cool cast. Those pixels fit the blue line
    # with a tiny alpha and would inflate the TV bounding box. Keep partial
    # alpha only next to real letter pixels.
    return _keep_fringe(tv, width, height), _keep_fringe(maestro, width, height)


def _keep_fringe(mask: bytearray, width: int, height: int, core: int = 48, radius: int = 2) -> bytearray:
    near = bytearray(width * height)
    for y in range(height):
        row = y * width
        for x in range(width):
            if mask[row + x] < core:
                continue
            y0 = max(0, y - radius)
            y1 = min(height, y + radius + 1)
            x0 = max(0, x - radius)
            x1 = min(width, x + radius + 1)
            for yy in range(y0, y1):
                dest = yy * width
                for xx in range(x0, x1):
                    near[dest + xx] = 1
    out = bytearray(width * height)
    for index, alpha in enumerate(mask):
        if near[index]:
            out[index] = alpha
    return out


def mask_bbox(mask: bytearray | bytes, width: int, height: int) -> tuple[int, int, int, int]:
    min_x, min_y = width, height
    max_x, max_y = -1, -1
    for y in range(height):
        row = y * width
        for x in range(width):
            if mask[row + x]:
                if x < min_x:
                    min_x = x
                if x > max_x:
                    max_x = x
                if y < min_y:
                    min_y = y
                if y > max_y:
                    max_y = y
    if max_x < 0:
        raise RuntimeError("mask has no ink")
    return min_x, min_y, max_x, max_y


def crop_mask(
    mask: bytes | bytearray,
    width: int,
    box: tuple[int, int, int, int],
) -> tuple[bytes, int, int]:
    x0, y0, x1, y1 = box
    cropped_w = x1 - x0 + 1
    cropped_h = y1 - y0 + 1
    out = bytearray(cropped_w * cropped_h)
    for y in range(cropped_h):
        src = (y0 + y) * width + x0
        dst = y * cropped_w
        out[dst : dst + cropped_w] = mask[src : src + cropped_w]
    return bytes(out), cropped_w, cropped_h


def paint(mask: bytes, color: Rgb) -> bytes:
    red, green, blue = color
    rgba = bytearray(len(mask) * 4)
    for index, alpha in enumerate(mask):
        if not alpha:
            continue
        offset = index * 4
        rgba[offset] = red
        rgba[offset + 1] = green
        rgba[offset + 2] = blue
        rgba[offset + 3] = alpha
    return bytes(rgba)


def composite(base: bytes, over: bytes) -> bytes:
    out = bytearray(base)
    for index in range(0, len(over), 4):
        if over[index + 3] > out[index + 3]:
            out[index : index + 4] = over[index : index + 4]
    return bytes(out)


def resize_height(src: Path, dest: Path, height: int) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    # Plain Lanczos keeps straight alpha. Associating alpha first turns the
    # transparent field opaque black in this ImageMagick build.
    magick(
        [
            str(src),
            "-filter",
            "Lanczos",
            "-resize",
            f"x{height}",
            f"PNG32:{dest}",
        ]
    )


def square_mark(mark: Path, size: int, dest: Path, background: str | None) -> None:
    """Center the TV mark at the same proportion as the existing app icon."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    target_w = max(1, round(size * MARK_WIDTH_RATIO))
    canvas = "none" if background is None else f"#{background}"
    magick(
        [
            "-size",
            f"{size}x{size}",
            f"xc:{canvas}",
            "(",
            str(mark),
            "-filter",
            "Lanczos",
            "-resize",
            f"{target_w}x",
            ")",
            "-gravity",
            "center",
            "-compose",
            "over",
            "-composite",
            f"PNG32:{dest}",
        ]
    )


def banner(wordmark: Path, width: int, height: int, dest: Path, background: str) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    target_w = max(1, round(width * BANNER_WIDTH_RATIO))
    magick(
        [
            "-size",
            f"{width}x{height}",
            f"xc:#{background}",
            "(",
            str(wordmark),
            "-filter",
            "Lanczos",
            "-resize",
            f"{target_w}x",
            ")",
            "-gravity",
            "center",
            "-compose",
            "over",
            "-composite",
            f"PNG32:{dest}",
        ]
    )


def _upscale_mask(mask: bytes, width: int, height: int, scale: int) -> tuple[bytes, int, int]:
    if scale == 1:
        return mask, width, height
    scaled_w = width * scale
    scaled_h = height * scale
    raw = magick(
        [
            "-size",
            f"{width}x{height}",
            "-depth",
            "8",
            "gray:-",
            "-filter",
            "Mitchell",
            "-resize",
            f"{scaled_w}x{scaled_h}!",
            "-depth",
            "8",
            "gray:-",
        ],
        data=mask,
        capture=True,
    )
    if len(raw) != scaled_w * scaled_h:
        raise RuntimeError("upscaled mask size mismatch")
    return raw, scaled_w, scaled_h


def _trace_d(mask: bytes, width: int, height: int, scale: int) -> str:
    import numpy as np
    from potrace import Bitmap

    gray, scaled_w, scaled_h = _upscale_mask(mask, width, height, scale)
    ink = np.frombuffer(gray, dtype=np.uint8).reshape(scaled_h, scaled_w) >= 128
    # Bitmap inverts its input, so pass the negative and it traces the ink.
    curves = Bitmap(~ink).trace(turdsize=2, alphamax=1.0, opticurve=True, opttolerance=0.2)
    commands: list[str] = []
    for curve in curves:
        start = curve.start_point
        commands.append(f"M{start.x / scale:.2f} {start.y / scale:.2f}")
        for segment in curve.segments:
            if segment.is_corner:
                commands.append(
                    f"L{segment.c.x / scale:.2f} {segment.c.y / scale:.2f}"
                    f" L{segment.end_point.x / scale:.2f} {segment.end_point.y / scale:.2f}"
                )
            else:
                commands.append(
                    f"C{segment.c1.x / scale:.2f} {segment.c1.y / scale:.2f}"
                    f" {segment.c2.x / scale:.2f} {segment.c2.y / scale:.2f}"
                    f" {segment.end_point.x / scale:.2f} {segment.end_point.y / scale:.2f}"
                )
        commands.append("Z")
    return " ".join(commands)


def _svg(width: int, height: int, paths: list[tuple[str, str]], title: str) -> str:
    body = "\n".join(
        f'  <path fill="#{color}" fill-rule="evenodd" d="{d}"/>'
        for color, d in paths
        if d
    )
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" '
        f'role="img" aria-label="{title}">\n'
        f"  <title>{title}</title>\n"
        f"{body}\n"
        f"</svg>\n"
    )


def write_svg(path: Path, width: int, height: int, paths: list[tuple[str, str]], title: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(_svg(width, height, paths, title), encoding="utf-8")


def hex_color(color: Rgb) -> str:
    return f"{color[0]:02X}{color[1]:02X}{color[2]:02X}"


def write_preview() -> None:
    def swatch(src: str, background: str, kind: str) -> str:
        return (
            f'<figure class="swatch {background} {kind}">'
            f'<img src="{src}" alt="">'
            f"<figcaption>{src}</figcaption>"
            f"</figure>"
        )

    wordmark_rows = []
    for name, _tv, _ma in WORDMARKS:
        light = swatch(f"wordmark/{name}/h128.png", "light", "word")
        dark = swatch(f"wordmark/{name}/h128.png", "dark", "word")
        wordmark_rows.append(
            f'<section><h2>{name}</h2><div class="row">{light}{dark}</div></section>'
        )
    vector_bits = []
    for name in SVG_WORDMARKS:
        vector_bits.append(swatch(f"wordmark/{name}.svg", "light", "vector"))
        vector_bits.append(swatch(f"wordmark/{name}.svg", "dark", "vector"))
    mark_bits = []
    for name, _color in MARKS:
        mark_bits.append(swatch(f"mark/{name}/s180.png", "light", "mark"))
        mark_bits.append(swatch(f"mark/{name}/s180.png", "dark", "mark"))
    mark_bits.append(swatch("mark/blue.svg", "light", "mark"))
    mark_bits.append(swatch("mark/blue.svg", "dark", "mark"))
    plates = [
        "plate/icon-dark-512.png",
        "plate/icon-light-512.png",
        "plate/icon-blue-512.png",
        "plate/icon-dark-1024.png",
        "plate/banner-dark-640x360.png",
        "plate/banner-dark-320x180.png",
        "plate/banner-light-640x360.png",
    ]
    plate_bits = "".join(
        f'<figure class="plate"><img src="{src}" alt=""><figcaption>{src}</figcaption></figure>'
        for src in plates
    )
    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>TV Maestro logo kit</title>
  <style>
    :root {{ color-scheme: light; }}
    body {{
      margin: 0;
      padding: 32px;
      font-family: "DM Sans", system-ui, sans-serif;
      background: #f3f5f8;
      color: #222931;
    }}
    h1 {{ font-size: 1.4rem; font-weight: 650; margin: 0 0 0.3rem; }}
    h2 {{ font-size: 0.95rem; font-weight: 650; margin: 1.6rem 0 0.6rem; }}
    p {{ max-width: 46rem; color: #3c4652; line-height: 1.45; }}
    .row {{ display: flex; flex-wrap: wrap; gap: 12px; align-items: stretch; }}
    figure {{ margin: 0; }}
    figcaption {{
      margin-top: 6px;
      font: 11px/1.3 ui-monospace, monospace;
      color: #5c6773;
      word-break: break-all;
    }}
    .swatch {{
      padding: 18px 22px 12px;
      border-radius: 10px;
      min-width: 280px;
    }}
    .light {{ background: #fff; border: 1px solid #e1e5eb; }}
    .dark {{ background: #0e1218; }}
    .dark figcaption {{ color: #8b9bb0; }}
    .word img {{ height: 48px; width: auto; display: block; }}
    .vector img {{ height: 88px; width: auto; display: block; }}
    .mark img {{ height: 96px; width: auto; display: block; }}
    .plate img {{
      display: block;
      height: 140px;
      width: auto;
      background: #d5dbe3;
    }}
    .plates {{ display: flex; flex-wrap: wrap; gap: 16px; align-items: end; }}
  </style>
</head>
<body>
  <h1>TV Maestro logo kit</h1>
  <p>
    Recolors of branding/logo-source.png. Canonical is the template:
    TV #2764AF, MAESTRO #222931. Each transparent lockup is shown on white
    and on the app background #0E1218.
  </p>
  {"".join(wordmark_rows)}
  <h2>Vectors</h2>
  <div class="row">{"".join(vector_bits)}</div>
  <h2>TV mark</h2>
  <div class="row">{"".join(mark_bits)}</div>
  <h2>Plates</h2>
  <div class="plates">{plate_bits}</div>
</body>
</html>
"""
    (KIT / "preview.html").write_text(html, encoding="utf-8")


def main() -> None:
    if not SOURCE.is_file():
        sys.exit(f"missing source logo: {SOURCE}")
    if shutil.which("magick") is None:
        sys.exit("ImageMagick (`magick`) is required")
    try:
        import numpy  # noqa: F401
        import potrace  # noqa: F401
    except ImportError:
        sys.exit("SVG tracing needs the pure-Python potrace package: pip install potracer")

    print(f"reading {SOURCE.relative_to(ROOT)}")
    width, height, rgba = read_rgba(SOURCE)
    tv, maestro = split_masks(width, height, rgba)
    union = mask_bbox(
        bytearray(a or b for a, b in zip(tv, maestro)),
        width,
        height,
    )
    tv_mask, mark_w, mark_h = crop_mask(tv, width, union)
    maestro_mask, _, _ = crop_mask(maestro, width, union)
    print(f"wordmark {mark_w}x{mark_h}")

    if KIT.exists():
        shutil.rmtree(KIT)
    KIT.mkdir(parents=True)

    colors = {name: (tv_color, ma_color) for name, tv_color, ma_color in WORDMARKS}
    with tempfile.TemporaryDirectory(prefix="tvmaestro-logo-") as tmp:
        temp = Path(tmp)
        masters: dict[str, Path] = {}
        for name, tv_color, ma_color in WORDMARKS:
            folder = KIT / "wordmark" / name
            master = folder / "h-master.png"
            painted = composite(paint(tv_mask, tv_color), paint(maestro_mask, ma_color))
            write_rgba(master, mark_w, mark_h, painted)
            masters[name] = master
            for logo_h in WORDMARK_HEIGHTS:
                resize_height(master, folder / f"h{logo_h}.png", logo_h)
            print(f"wordmark {name}")

        for name in SVG_WORDMARKS:
            tv_color, ma_color = colors[name]
            write_svg(
                KIT / "wordmark" / f"{name}.svg",
                mark_w,
                mark_h,
                [
                    (hex_color(tv_color), _trace_d(tv_mask, mark_w, mark_h, TRACE_SCALE)),
                    (hex_color(ma_color), _trace_d(maestro_mask, mark_w, mark_h, TRACE_SCALE)),
                ],
                "TV Maestro",
            )
            print(f"svg {name}")

        tv_box = mask_bbox(tv_mask, mark_w, mark_h)
        tv_only, tv_w, tv_h = crop_mask(tv_mask, mark_w, tv_box)
        print(f"mark {tv_w}x{tv_h}")
        tight: dict[str, Path] = {}
        for name, color in MARKS:
            path = temp / f"mark-{name}.png"
            write_rgba(path, tv_w, tv_h, paint(tv_only, color))
            tight[name] = path
            for size in MARK_SIZES:
                square_mark(path, size, KIT / "mark" / name / f"s{size}.png", None)
            print(f"mark {name}")

        write_svg(
            KIT / "mark" / "blue.svg",
            tv_w,
            tv_h,
            [(hex_color(BLUE), _trace_d(tv_only, tv_w, tv_h, TRACE_SCALE))],
            "TV",
        )

        for size in (512, 1024):
            square_mark(tight["blue"], size, KIT / "plate" / f"icon-dark-{size}.png", APP_BG)
            square_mark(tight["blue"], size, KIT / "plate" / f"icon-light-{size}.png", "FFFFFF")
            square_mark(tight["white"], size, KIT / "plate" / f"icon-blue-{size}.png", hex_color(BLUE))
        banner(masters["on-dark"], 640, 360, KIT / "plate" / "banner-dark-640x360.png", APP_BG)
        banner(masters["on-dark"], 320, 180, KIT / "plate" / "banner-dark-320x180.png", APP_BG)
        banner(masters["canonical"], 640, 360, KIT / "plate" / "banner-light-640x360.png", "FFFFFF")
        print("plates")

    write_preview()
    print(f"wrote {KIT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
