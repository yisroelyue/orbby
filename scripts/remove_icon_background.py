"""Create the Orbby icon with a rounded green background and transparent edges.

Usage:
    python scripts/remove_icon_background.py input.png output.png
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path

from PIL import Image


def color_distance(rgb: tuple[int, int, int], target: tuple[int, int, int]) -> float:
    return math.sqrt(sum((a - b) ** 2 for a, b in zip(rgb, target)))


def foreground_alpha(rgb: tuple[int, int, int]) -> int:
    """Return alpha for the white ring or cyan node, otherwise transparent."""
    white = color_distance(rgb, (255, 255, 255))
    cyan = color_distance(rgb, (40, 225, 235))

    # Keep the two intended foreground colors and their antialiased edges.
    nearest = min(white, cyan)
    if nearest >= 115:
        return 0
    return round((1 - nearest / 115) * 255)


def create_icon(source: Path, destination: Path) -> None:
    image = Image.open(source).convert("RGBA")
    foreground = Image.new("RGBA", image.size, (0, 0, 0, 0))
    pixels = []

    for red, green, blue, _ in image.getdata():
        alpha = foreground_alpha((red, green, blue))
        # Use clean source colors; alpha carries the soft edge.
        if color_distance((red, green, blue), (255, 255, 255)) <= color_distance(
            (red, green, blue), (40, 225, 235)
        ):
            color = (255, 255, 255)
        else:
            color = (40, 225, 235)
        pixels.append((*color, alpha))

    foreground.putdata(pixels)

    # Rounded green tile; the corners outside it remain fully transparent.
    background = Image.new("RGBA", image.size, (0, 0, 0, 0))
    # Larger radius only changes the tile corners; the icon foreground stays unchanged.
    radius = round(min(image.size) * 0.27)
    margin = round(min(image.size) * 0.035)
    from PIL import ImageDraw
    ImageDraw.Draw(background).rounded_rectangle(
        (margin, margin, image.width - margin - 1, image.height - margin - 1),
        radius=radius,
        fill=(69, 166, 106, 255),
    )

    output = Image.alpha_composite(background, foreground)
    destination.parent.mkdir(parents=True, exist_ok=True)
    output.save(destination, "PNG")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="source icon PNG")
    parser.add_argument("output", type=Path, help="transparent PNG destination")
    args = parser.parse_args()
    create_icon(args.input, args.output)


if __name__ == "__main__":
    main()
