"""
Generate an icon: 8 colorful dots arranged in a circle with wave-varying sizes.
Captures the animated pulse-wave effect from Orbby's colorful pet ball.

Usage: python generate_icon-colorful.py [output_path] [size] [phase_offset]

Requirements: pip install pillow
"""

import math
import sys
from PIL import Image, ImageDraw

# ---- Config ----
SIZE = 256                     # default icon size in pixels
DOT_COUNT = 8

# Proportions matching Flutter's _ColorfulDotsState:
#   _dotRadius = PetConfig.ballSize * 0.1
#   _circleRadius = PetConfig.ballSize / 2 - _dotRadius
# Expressed as ratios of SIZE/2:
DOT_RADIUS_RATIO = 0.20       # max dot radius / (SIZE/2)
CIRCLE_RADIUS_RATIO = 0.80    # ring radius / (SIZE/2)

# Wave scale range matching Flutter: scale = 0.35 + 0.65 * sin(phase * pi)
SCALE_MIN = 0.35
SCALE_MAX = 1.0

# Colors from lib/widgets/pet_ball_colorful.dart _dotColors
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


def wave_scale(index: int, count: int, phase_offset: float = 0.0) -> float:
    """Compute the pulse-wave scale for a dot at the given index.

    Replicates Flutter's animation:
        delay = i / _dotCount
        phase = (_controller.value + delay) % 1.0
        scale = 0.35 + 0.65 * sin(phase * pi)

    Each dot has a different delay offset, creating the traveling-wave effect
    where dots pulse in sequence around the ring.
    """
    delay = index / count
    phase = (phase_offset + delay) % 1.0
    return SCALE_MIN + (SCALE_MAX - SCALE_MIN) * math.sin(phase * math.pi)


def create_icon(size: int = SIZE, phase_offset: float = 0.0) -> Image.Image:
    """Create a transparent image with 8 colored dots in a circle.

    Dots have varying sizes following the sin-wave pulse animation pattern:
    dots grow from smallest at the top (coral) to largest at the bottom
    (blue), then shrink back, symmetric on both sides.
    """
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    cx = cy = size / 2.0
    base_dot_radius = size / 2.0 * DOT_RADIUS_RATIO
    ring_radius = size / 2.0 * CIRCLE_RADIUS_RATIO

    for i in range(DOT_COUNT):
        # Angle: evenly spaced, starting from top (-pi/2), matching Flutter
        angle = (i / DOT_COUNT) * 2 * math.pi - math.pi / 2

        # Varying radius: captures one frame of the traveling-wave animation
        scale = wave_scale(i, DOT_COUNT, phase_offset)
        dot_radius = base_dot_radius * scale

        x = cx + ring_radius * math.cos(angle)
        y = cy + ring_radius * math.sin(angle)

        bbox = (x - dot_radius, y - dot_radius, x + dot_radius, y + dot_radius)
        draw.ellipse(bbox, fill=COLORS[i])

    return img


def main():
    output_path = sys.argv[1] if len(sys.argv) > 1 else "orbby_icon.png"
    size = int(sys.argv[2]) if len(sys.argv) > 2 else SIZE
    # Default: smallest dot at bottom-right (index 3). phase_offset = -3/8 + k, k∈Z
    phase_offset = float(sys.argv[3]) if len(sys.argv) > 3 else -0.375

    img = create_icon(size, phase_offset)
    img.save(output_path, "PNG")
    print(f"Icon saved -> {output_path}  ({size}x{size} px, RGBA)")
    print(f"  Phase offset: {phase_offset}")
    print(f"  Dot scales: {', '.join(f'{wave_scale(i, DOT_COUNT, phase_offset):.2f}' for i in range(DOT_COUNT))}")


if __name__ == "__main__":
    main()
