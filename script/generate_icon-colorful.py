"""
Generate an icon: 8 colorful balls arranged in a circle on transparent background.
Based on the colorful pet ball style from Orbby.

Usage: python generate_icon.py [output_path] [size]

Requirements: pip install pillow
"""

import math
import sys
from PIL import Image, ImageDraw

# ---- Config ----
SIZE = 256                     # default icon size in pixels
DOT_COUNT = 8
DOT_RADIUS_RATIO = 0.16       # dot radius = SIZE/2 * ratio
CIRCLE_RADIUS_RATIO = 0.60    # ring radius = SIZE/2 * ratio

# Colors from Flutter code (_ColorfulDotsState._dotColors)
COLORS = [
    (0xFF, 0x6B, 0x6B),  # coral
    (0xFF, 0x9F, 0x43),  # orange
    (0xFF, 0xD9, 0x3D),  # gold
    (0x6B, 0xCB, 0x77),  # green
    (0x54, 0xA0, 0xFF),  # blue
    (0x5F, 0x27, 0xCD),  # purple
    (0xFF, 0x6B, 0x9D),  # pink
    (0x00, 0xD2, 0xD3),  # teal
]


def create_icon(size: int = SIZE) -> Image.Image:
    """Create a transparent image with 8 colored dots in a ring."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    cx = cy = size / 2.0
    dot_radius = size / 2.0 * DOT_RADIUS_RATIO
    ring_radius = size / 2.0 * CIRCLE_RADIUS_RATIO

    for i in range(DOT_COUNT):
        # Angle: evenly spaced, starting from top (-pi/2), matching Flutter
        angle = (i / DOT_COUNT) * 2 * math.pi - math.pi / 2
        x = cx + ring_radius * math.cos(angle)
        y = cy + ring_radius * math.sin(angle)

        bbox = (x - dot_radius, y - dot_radius, x + dot_radius, y + dot_radius)
        draw.ellipse(bbox, fill=COLORS[i])

    return img


def main():
    output_path = sys.argv[1] if len(sys.argv) > 1 else "orbby_icon.png"
    size = int(sys.argv[2]) if len(sys.argv) > 2 else SIZE

    img = create_icon(size)
    img.save(output_path, "PNG")
    print(f"Icon saved -> {output_path}  ({size}x{size} px, RGBA)")


if __name__ == "__main__":
    main()
