#!/usr/bin/env python3
"""Flip all images in a folder horizontally.

Results are always saved to a new folder — originals are never touched.

Usage:
    python flip_images.py <folder>                    # → <folder>_flipped/
    python flip_images.py <folder> -o output_dir/     # → custom output dir
    python flip_images.py <folder> --overwrite         # overwrite originals
    python flip_images.py <folder> --no-recursive      # top-level only
"""

import argparse
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("Error: Pillow is required. Install it with:  pip install pillow")
    sys.exit(1)

EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp", ".bmp", ".gif", ".tiff", ".tif"}


def flip_image(src: Path, dst: Path) -> None:
    with Image.open(src) as img:
        flipped = img.transpose(Image.FLIP_LEFT_RIGHT)
        fmt = img.format if img.format else "PNG"
        flipped.save(dst, format=fmt)
    print(f"  ✓ {src.name} → {dst.name}")


def main():
    parser = argparse.ArgumentParser(
        description="Horizontally flip all images in a folder (saves to new folder)."
    )
    parser.add_argument(
        "folder", type=Path,
        help="Path to the folder containing images.",
    )
    parser.add_argument(
        "-o", "--output", type=Path, default=None,
        help="Output directory (default: <folder>_flipped/).",
    )
    parser.add_argument(
        "--overwrite", action="store_true",
        help="Overwrite original files instead of creating a new folder.",
    )
    parser.add_argument(
        "--no-recursive", action="store_true",
        help="Only process top-level files, not subdirectories.",
    )

    args = parser.parse_args()
    folder: Path = args.folder.resolve()

    if not folder.is_dir():
        print(f"Error: '{folder}' is not a valid directory.")
        sys.exit(1)

    # Collect images
    pattern = "**/*" if not args.no_recursive else "*"
    images = [
        p for p in folder.glob(pattern)
        if p.is_file() and p.suffix.lower() in EXTENSIONS
    ]

    if not images:
        print(f"No images found in '{folder}'.")
        sys.exit(0)

    # Determine output directory
    if args.overwrite:
        out_dir = None
    elif args.output:
        out_dir = args.output.resolve()
    else:
        out_dir = folder.parent / (folder.name + "_flipped")

    if out_dir:
        out_dir.mkdir(parents=True, exist_ok=True)

    print(f"Found {len(images)} image(s) in '{folder}'.")
    if out_dir:
        print(f"Saving to '{out_dir}/'\n")
    else:
        print("Overwriting originals.\n")

    count = 0
    for src in images:
        if out_dir:
            rel = src.relative_to(folder)
            dst = out_dir / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
        else:
            dst = src

        try:
            flip_image(src, dst)
            count += 1
        except Exception as e:
            print(f"  ✗ {src.name}: {e}")

    print(f"\nDone. Flipped {count}/{len(images)} image(s).")


if __name__ == "__main__":
    main()
