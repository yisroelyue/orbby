#!/usr/bin/env python3
"""Remove white edges / fringe from PNG sprites.

Two strategies are applied:
  1. White-to-alpha  — near-white pixels become transparent
  2. Alpha-edge fix  — semi-transparent edges get their RGB darkened
                       to compensate for white-background blending

Usage:
    python defringe.py <folder>                    # → <folder>_defringed/
    python defringe.py <folder> --overwrite         # replace originals
    python defringe.py <folder> --white-thresh 200  # more aggressive (default 230)
    python defringe.py <folder> --edge-thresh 100   # edge fix threshold (default 128)
"""

import argparse
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("Error: Pillow is required. Install it with:  pip install pillow")
    sys.exit(1)

EXTENSIONS = {".png", ".webp", ".bmp", ".tiff", ".tif"}


def fix_pixel(r: int, g: int, b: int, a: int,
              white_thresh: int, edge_thresh: int) -> tuple[int, int, int, int]:
    """Fix a single pixel's white fringe."""

    # ── Strategy 1: near-white → transparent ──
    # If all three channels are above the white threshold, nuke the pixel.
    if a >= edge_thresh and r >= white_thresh and g >= white_thresh and b >= white_thresh:
        return (0, 0, 0, 0)

    if a <= 0:
        return (0, 0, 0, 0)

    # ── Strategy 2: reverse white-background compositing ──
    # visible = real * a/255 + 255 * (1 - a/255)
    # → real = 255 + (visible - 255) * 255 / a
    if a < 255:
        alpha_f = a / 255.0
        def unbleed(c: int) -> int:
            raw = round(255 + (c - 255) / alpha_f)
            return max(0, min(255, raw))

        r2, g2, b2 = unbleed(r), unbleed(g), unbleed(b)

        # If the result is near-black with decent alpha, keep it
        return (r2, g2, b2, a)

    return (r, g, b, a)


def process_image(src: Path, dst: Path, white_thresh: int, edge_thresh: int) -> None:
    with Image.open(src) as img:
        if img.mode != "RGBA":
            img = img.convert("RGBA")

        pixels = img.load()
        w, h = img.size

        for y in range(h):
            for x in range(w):
                r, g, b, a = pixels[x, y]
                pixels[x, y] = fix_pixel(r, g, b, a, white_thresh, edge_thresh)

        fmt = img.format if img.format else "PNG"
        img.save(dst, format=fmt)
    print(f"  ✓ {src.name}")


def main():
    parser = argparse.ArgumentParser(
        description="Remove white fringe / edges from PNG sprites."
    )
    parser.add_argument("folder", type=Path, help="Folder containing images.")
    parser.add_argument("-o", "--output", type=Path, default=None,
                        help="Output directory (default: <folder>_defringed/).")
    parser.add_argument("--overwrite", action="store_true",
                        help="Overwrite original files.")
    parser.add_argument("--white-thresh", type=int, default=230,
                        help="Whiteness threshold (0-255, lower = more aggressive). Default: 230")
    parser.add_argument("--edge-thresh", type=int, default=128,
                        help="Min alpha to consider a pixel for white-removal. Default: 128")
    parser.add_argument("--no-recursive", action="store_true",
                        help="Only process top-level files.")

    args = parser.parse_args()
    folder: Path = args.folder.resolve()

    if not folder.is_dir():
        print(f"Error: '{folder}' is not a valid directory.")
        sys.exit(1)

    pattern = "**/*" if not args.no_recursive else "*"
    images = [p for p in folder.glob(pattern)
              if p.is_file() and p.suffix.lower() in EXTENSIONS]

    if not images:
        print(f"No images found in '{folder}'.")
        sys.exit(0)

    if args.overwrite:
        out_dir = None
    elif args.output:
        out_dir = args.output.resolve()
    else:
        out_dir = folder.parent / (folder.name + "_defringed")

    if out_dir:
        out_dir.mkdir(parents=True, exist_ok=True)

    print(f"Found {len(images)} image(s).")
    print(f"  white-thresh={args.white_thresh}, edge-thresh={args.edge_thresh}\n")

    count = 0
    for src in images:
        if out_dir:
            rel = src.relative_to(folder)
            dst = out_dir / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
        else:
            dst = src
        try:
            process_image(src, dst, args.white_thresh, args.edge_thresh)
            count += 1
        except Exception as e:
            print(f"  ✗ {src.name}: {e}")

    print(f"\nDone. Processed {count}/{len(images)} image(s).")


if __name__ == "__main__":
    main()
