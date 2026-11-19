#!/usr/bin/env python3
"""Generate Burner's app icons and splash images for Android, web and Linux.

The artwork is the Material `local_fire_department` glyph (the flame used in
the app UI) rendered from Flutter's bundled MaterialIcons font, filled with an
ember gradient on a dark background.

Usage (from the repo root):
    python3 tool/generate_icons.py [path/to/MaterialIcons-Regular.otf]

Without an argument the font is located through the `flutter` on PATH.
Requires Pillow.
"""

import os
import shutil
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FLAME_CODEPOINT = 0xE392  # Icons.local_fire_department
BACKGROUND = (0x20, 0x1A, 0x17)  # keep in sync with BurnerTheme.splashBackground
FLAME_TOP = (0xE8, 0x59, 0x0C)  # BurnerTheme.seed
FLAME_BOTTOM = (0xFF, 0xB0, 0x4D)


def find_font():
    if len(sys.argv) > 1:
        return sys.argv[1]
    flutter = shutil.which("flutter")
    if not flutter:
        sys.exit("flutter not on PATH; pass the MaterialIcons-Regular.otf path")
    sdk = os.path.dirname(os.path.dirname(os.path.realpath(flutter)))
    path = os.path.join(sdk, "bin", "cache", "artifacts", "material_fonts",
                        "MaterialIcons-Regular.otf")
    if not os.path.exists(path):
        sys.exit(f"font not found at {path}; run `flutter precache` or pass a path")
    return path


def flame_mask(font_path, size):
    """Alpha mask of the flame glyph, tightly cropped, `size` px tall."""
    font = ImageFont.truetype(font_path, 2048)
    glyph = chr(FLAME_CODEPOINT)
    # Draw on a generous canvas and crop to the inked pixels: the font's
    # reported bbox can clip the glyph.
    mask = Image.new("L", (4096, 4096), 0)
    ImageDraw.Draw(mask).text((1024, 1024), glyph, font=font, fill=255)
    mask = mask.crop(mask.getbbox())
    width = max(1, round(mask.width * size / mask.height))
    return mask.resize((width, size), Image.LANCZOS)


def gradient(width, height):
    img = Image.new("RGB", (width, height))
    draw = ImageDraw.Draw(img)
    for y in range(height):
        t = y / max(1, height - 1)
        color = tuple(round(a + (b - a) * t) for a, b in zip(FLAME_TOP, FLAME_BOTTOM))
        draw.line([(0, y), (width, y)], fill=color)
    return img


def flame_on(canvas, font_path, scale):
    """Paste the gradient flame centered on `canvas`, `scale` of its height."""
    mask = flame_mask(font_path, round(canvas.height * scale))
    flame = gradient(mask.width, mask.height)
    x = (canvas.width - mask.width) // 2
    y = (canvas.height - mask.height) // 2
    canvas.paste(flame, (x, y), mask)
    return canvas


def rounded_icon(font_path, size, radius=0.22, scale=0.62):
    """Dark rounded square with the flame: launcher/favicon/desktop icon."""
    big = size * 4
    canvas = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    ImageDraw.Draw(canvas).rounded_rectangle(
        [0, 0, big - 1, big - 1], radius=round(big * radius), fill=BACKGROUND + (255,))
    flame_on(canvas, font_path, scale)
    return canvas.resize((size, size), Image.LANCZOS)


def full_bleed_icon(font_path, size, scale=0.5):
    """Square background to the edges (web maskable icons)."""
    big = size * 4
    canvas = Image.new("RGBA", (big, big), BACKGROUND + (255,))
    flame_on(canvas, font_path, scale)
    return canvas.resize((size, size), Image.LANCZOS)


def transparent_flame(font_path, size, scale):
    """Flame on transparent background (adaptive foreground, splash)."""
    big = size * 4
    canvas = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    flame_on(canvas, font_path, scale)
    return canvas.resize((size, size), Image.LANCZOS)


def save(img, *parts):
    path = os.path.join(ROOT, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, optimize=True)
    print("wrote", os.path.relpath(path, ROOT))


def main():
    font = find_font()

    # Source artwork (kept in the repo for reuse, e.g. store listings).
    save(rounded_icon(font, 1024), "assets", "branding", "icon.png")
    save(transparent_flame(font, 1024, 0.8), "assets", "branding", "flame.png")

    # Web: favicon, PWA icons, splash image.
    save(rounded_icon(font, 64), "web", "favicon.png")
    for size in (192, 512):
        save(rounded_icon(font, size), "web", "icons", f"Icon-{size}.png")
        save(full_bleed_icon(font, size), "web", "icons", f"Icon-maskable-{size}.png")
    save(transparent_flame(font, 256, 0.9), "web", "splash", "flame.png")

    # Android: legacy launcher icons (48dp), adaptive foregrounds (108dp, art
    # inside the 66dp safe zone) and pre-Android-12 splash image (96dp).
    densities = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    res = ("android", "app", "src", "main", "res")
    for name, factor in densities.items():
        save(rounded_icon(font, round(48 * factor)), *res, f"mipmap-{name}", "ic_launcher.png")
        save(transparent_flame(font, round(108 * factor), 0.42),
             *res, f"drawable-{name}", "ic_launcher_foreground.png")
        save(transparent_flame(font, round(96 * factor), 0.9),
             *res, f"drawable-{name}", "splash.png")

    # Linux: window/desktop icon.
    save(rounded_icon(font, 512), "linux", "icons", "burner.png")


if __name__ == "__main__":
    main()
