#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "Assets"
PNG_PATH = ASSETS / "DSkillerIcon-1024.png"


def rounded_rectangle_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size, size), radius=radius, fill=255)
    return mask


def font(size: int) -> ImageFont.FreeTypeFont:
    candidates = [
        "/System/Library/Fonts/SFNSRounded.ttf",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/Library/Fonts/Arial Bold.ttf",
    ]
    for candidate in candidates:
        try:
            return ImageFont.truetype(candidate, size)
        except OSError:
            continue
    return ImageFont.load_default()


def main() -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)
    size = 1024

    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow_mask = rounded_rectangle_mask(820, 185).filter(ImageFilter.GaussianBlur(34))
    shadow.alpha_composite(
        Image.new("RGBA", (820, 820), (0, 0, 0, 70)),
        (102, 130),
    )
    shadow.putalpha(Image.new("L", (size, size), 0))
    shadow_alpha = Image.new("L", (size, size), 0)
    shadow_alpha.paste(shadow_mask, (102, 130))
    shadow.putalpha(shadow_alpha)
    canvas.alpha_composite(shadow)

    tile = Image.new("RGBA", (820, 820), (248, 250, 252, 255))
    tile_mask = rounded_rectangle_mask(820, 185)
    tile_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    tile_layer.alpha_composite(tile, (102, 92))
    alpha = Image.new("L", (size, size), 0)
    alpha.paste(tile_mask, (102, 92))
    tile_layer.putalpha(alpha)
    canvas.alpha_composite(tile_layer)

    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle((102, 92, 922, 912), radius=185, outline=(203, 213, 225, 255), width=12)

    accent = Image.new("RGBA", (820, 820), (0, 0, 0, 0))
    accent_draw = ImageDraw.Draw(accent)
    accent_draw.rounded_rectangle((0, 0, 820, 820), radius=185, outline=(14, 165, 233, 70), width=34)
    canvas.alpha_composite(accent, (102, 92))

    label_font = font(318)
    label = "DS"
    text_box = draw.textbbox((0, 0), label, font=label_font)
    text_width = text_box[2] - text_box[0]
    text_height = text_box[3] - text_box[1]
    x = (size - text_width) / 2 - text_box[0]
    y = (size - text_height) / 2 - text_box[1] - 6

    draw.text((x + 6, y + 8), label, font=label_font, fill=(15, 23, 42, 54))
    draw.text((x, y), label, font=label_font, fill=(15, 23, 42, 255))

    dot_radius = 26
    draw.ellipse(
        (size / 2 - dot_radius, 742 - dot_radius, size / 2 + dot_radius, 742 + dot_radius),
        fill=(14, 165, 233, 255),
    )

    canvas.save(PNG_PATH)
    print(PNG_PATH)


if __name__ == "__main__":
    main()
