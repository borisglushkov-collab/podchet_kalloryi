#!/usr/bin/env python3
"""Собрать карточку «мягкое лето» в формате студии.

Ищет ваше фото в этой папке (photo.jpg / photo.jfif / …) и вклеивает его
слева. Лицо не генерирует.
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "карточка.png"

PHOTO_NAMES = (
    "photo.jpg",
    "photo.jpeg",
    "photo.jfif",
    "photo.png",
    "photo.webp",
    "фото.jpg",
    "фото.jpeg",
    "фото.jfif",
    "фото.png",
)

W, H = 2400, 1350
BG = (248, 246, 244)
INK = (42, 44, 48)
MUTED = (110, 112, 118)
LINE = (220, 216, 210)
NAVY = (59, 79, 107)

GRID = [
    [
        ("#3B4F6B", "база основа"),
        ("#565B63", "база"),
        ("#62788F", "база основа"),
        ("#8F8377", "база"),
        ("#B8A99A", "база"),
    ],
    [
        ("#7E93A8", "основа"),
        ("#6A8BAF", "основа"),
        ("#789486", "основа"),
        ("#8EA691", "основа"),
        ("#9B7A8A", "основа"),
    ],
    [
        ("#F0EEE9", "база"),
        ("#C5BFB0", "база"),
        ("#A8B0B5", "база"),
        ("#C894A0", "основа"),
        ("#A68F94", "основа"),
    ],
    [
        ("#9E5F73", "акцент"),
        ("#6F5C73", "акцент"),
        ("#876589", "акцент основа"),
        ("#765C5A", "база"),
        ("#5F7A6E", "основа"),
    ],
    [
        ("#B06A8A", "акцент"),
        ("#9B8FB0", "акцент основа"),
        ("#C5CBD0", "база"),
        ("#9AAD9A", "основа"),
        ("#C5D1C3", "основа"),
    ],
]


def hex_rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def luminance(rgb: tuple[int, int, int]) -> float:
    r, g, b = [c / 255 for c in rgb]
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def find_font(bold: bool) -> str:
    names_bold = [
        "C:/Windows/Fonts/arialbd.ttf",
        "C:/Windows/Fonts/calibrib.ttf",
        "C:/Windows/Fonts/segoeuib.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    ]
    names_reg = [
        "C:/Windows/Fonts/arial.ttf",
        "C:/Windows/Fonts/calibri.ttf",
        "C:/Windows/Fonts/segoeui.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    ]
    for path in names_bold if bold else names_reg:
        if Path(path).is_file():
            return path
    raise FileNotFoundError("Не найден шрифт с кириллицей (Arial / DejaVu).")


def font(bold: bool, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(find_font(bold), size)


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=255
    )
    return mask


def fit_cover(im: Image.Image, box: tuple[int, int]) -> Image.Image:
    tw, th = box
    iw, ih = im.size
    scale = max(tw / iw, th / ih)
    nw, nh = int(iw * scale + 0.5), int(ih * scale + 0.5)
    im = im.resize((nw, nh), Image.Resampling.LANCZOS)
    left = max(0, (nw - tw) // 2)
    top = max(0, int((nh - th) * 0.18))
    return im.crop((left, top, left + tw, top + th))


def find_photo() -> Path | None:
    extra = sys.argv[1:]
    for item in extra:
        p = Path(item)
        if p.is_file():
            return p
    for name in PHOTO_NAMES:
        p = ROOT / name
        if p.is_file():
            return p
    return None


def draw_placeholder(canvas: Image.Image, box: tuple[int, int, int, int]) -> None:
    x, y, w, h = box
    panel = Image.new("RGB", (w, h), NAVY)
    canvas.paste(panel, (x, y), rounded_mask((w, h), 18))
    draw = ImageDraw.Draw(canvas)

    def line(text: str, yy: int, f: ImageFont.FreeTypeFont, fill=(226, 230, 236)) -> None:
        bb = draw.textbbox((0, 0), text, font=f)
        draw.text((x + (w - (bb[2] - bb[0])) // 2, yy), text, font=f, fill=fill)

    line("положите своё фото", y + 70, font(False, 26), (210, 216, 224))
    line("мягкое лето", y + 120, font(True, 42), (255, 255, 255))
    for i, text in enumerate(
        [
            "42 года  ·  165 см  ·  110 кг",
            "рубашка 54  ·  regular",
            "",
            "скопируйте снимок в",
            "palette\\photo.jpg",
            "и запустите",
            "собрать-карточку.bat",
            "",
            "лицо не генерируется",
        ]
    ):
        line(text, y + 200 + i * 44, font(False, 22))


def paste_photo(canvas: Image.Image, photo_path: Path, box: tuple[int, int, int, int]) -> None:
    x, y, w, h = box
    im = Image.open(photo_path)
    if im.mode not in ("RGB", "L"):
        im = im.convert("RGB")
    else:
        im = im.convert("RGB")
    im = fit_cover(im, (w, h))
    canvas.paste(im, (x, y), rounded_mask((w, h), 18))


def main() -> None:
    photo = find_photo()
    canvas = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(canvas)

    f_header = font(False, 28)
    f_name = font(True, 48)
    f_meta = font(False, 24)
    f_swatch = font(False, 22)
    f_swatch2 = font(False, 20)
    f_legend = font(False, 24)

    draw.rectangle((0, 0, W, 86), fill=(255, 255, 255))
    draw.line((0, 86, W, 86), fill=LINE, width=2)
    header = "персональная палитра  ·  мягкое лето  ·  рубашка 54"
    hb = draw.textbbox((0, 0), header, font=f_header)
    draw.text(((W - (hb[2] - hb[0])) // 2, 28), header, font=f_header, fill=MUTED)

    col_x, photo_top = 70, 168
    photo_w, photo_h = 620, 980
    name = "мягкое лето"
    nb = draw.textbbox((0, 0), name, font=f_name)
    draw.text((col_x + (photo_w - (nb[2] - nb[0])) // 2, 98), name, font=f_name, fill=INK)

    box = (col_x, photo_top, photo_w, photo_h)
    if photo:
        paste_photo(canvas, photo, box)
        print(f"фото: {photo}")
    else:
        draw_placeholder(canvas, box)
        print("фото не найдено — слева заглушка. Положите photo.jpg в эту папку.")

    meta = "42 года  ·  165 см  ·  110 кг  ·  размер 54"
    mb = draw.textbbox((0, 0), meta, font=f_meta)
    draw.text(
        (col_x + (photo_w - (mb[2] - mb[0])) // 2, photo_top + photo_h + 18),
        meta,
        font=f_meta,
        fill=MUTED,
    )
    note = "крой regular / classic  ·  не slim"
    nb2 = draw.textbbox((0, 0), note, font=f_meta)
    draw.text(
        (col_x + (photo_w - (nb2[2] - nb2[0])) // 2, photo_top + photo_h + 50),
        note,
        font=f_meta,
        fill=(150, 150, 154),
    )

    gx, gy = 740, 120
    gap = 14
    usable_w = W - gx - 70
    usable_h = 1080
    cell = min((usable_w - 4 * gap) // 5, (usable_h - 4 * gap) // 5)
    grid_w = 5 * cell + 4 * gap
    gx = 740 + (usable_w - grid_w) // 2

    for r, row in enumerate(GRID):
        for c, (hexcode, label) in enumerate(row):
            x = gx + c * (cell + gap)
            y = gy + r * (cell + gap)
            rgb = hex_rgb(hexcode)
            sw = Image.new("RGB", (cell, cell), rgb)
            canvas.paste(sw, (x, y), rounded_mask((cell, cell), 12))
            ink = (255, 255, 255) if luminance(rgb) < 0.58 else (36, 36, 40)
            words = label.split()
            draw = ImageDraw.Draw(canvas)
            if len(words) == 1:
                tb = draw.textbbox((0, 0), words[0], font=f_swatch)
                draw.text(
                    (x + (cell - (tb[2] - tb[0])) / 2, y + cell - (tb[3] - tb[1]) - 18),
                    words[0],
                    font=f_swatch,
                    fill=ink,
                )
            else:
                t1, t2 = words[0], " ".join(words[1:])
                b1 = draw.textbbox((0, 0), t1, font=f_swatch2)
                b2 = draw.textbbox((0, 0), t2, font=f_swatch2)
                y1 = y + cell - 48
                draw.text((x + (cell - (b1[2] - b1[0])) / 2, y1), t1, font=f_swatch2, fill=ink)
                draw.text((x + (cell - (b2[2] - b2[0])) / 2, y1 + 22), t2, font=f_swatch2, fill=ink)

    legend_y = gy + 5 * cell + 4 * gap + 28
    legend = "база — нейтрали гардероба     основа — рабочие цвета     акцент — 10% образа"
    lb = draw.textbbox((0, 0), legend, font=f_legend)
    draw.text((gx + (grid_w - (lb[2] - lb[0])) // 2, legend_y), legend, font=f_legend, fill=MUTED)

    canvas.save(OUT, "PNG", optimize=True)
    print(f"готово: {OUT}")


if __name__ == "__main__":
    main()
