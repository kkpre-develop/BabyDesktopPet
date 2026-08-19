#!/usr/bin/env python3
"""Simple white-background removal for baby photos using flood-fill."""
from PIL import Image, ImageDraw
import os


def remove_white_bg(input_path: str, output_path: str, threshold: int = 250):
    img = Image.open(input_path).convert("RGBA")
    w, h = img.size

    # Create a binary mask: 255 = candidate foreground, 0 = background
    # Start by marking near-white pixels as 0 (background), others 255.
    gray = img.convert("L")
    mask = gray.point(lambda x: 0 if x >= threshold else 255, mode="L")

    # Flood-fill from the four borders to remove any white background islands.
    # Use a fresh working mask to avoid mutating while iterating.
    work = mask.copy()
    draw = ImageDraw.Draw(work)
    border_seeds = []
    for x in range(w):
        border_seeds.append((x, 0))
        border_seeds.append((x, h - 1))
    for y in range(h):
        border_seeds.append((0, y))
        border_seeds.append((w - 1, y))

    for x, y in border_seeds:
        if work.getpixel((x, y)) == 0:
            # Pixel is already background; flood it to ensure connectivity.
            ImageDraw.floodfill(work, (x, y), 0, thresh=0)

    # Anything that remains 0 in `work` is background; convert to transparent.
    alpha = work.point(lambda x: 255 if x == 255 else 0, mode="L")

    # Optional: shrink tight bounding box around non-transparent pixels.
    bbox = alpha.getbbox()
    if bbox:
        img.putalpha(alpha)
        cropped = img.crop(bbox)
        # Add a small transparent padding so edges don't clip.
        pad = 10
        padded = Image.new("RGBA", (cropped.width + pad * 2, cropped.height + pad * 2), (0, 0, 0, 0))
        padded.paste(cropped, (pad, pad), cropped)
        padded.save(output_path)
    else:
        img.putalpha(alpha)
        img.save(output_path)


if __name__ == "__main__":
    base = "/Users/shmiyangkuan/WorkBuddy/2026-08-17-13-59-18/output"
    os.makedirs(base, exist_ok=True)
    inputs = [
        "/Users/shmiyangkuan/Downloads/宝宝照片/微信图片_20260817141407_13_1008.jpg",
        "/Users/shmiyangkuan/Downloads/宝宝照片/微信图片_20260817141409_15_1008.jpg",
    ]
    for i, inp in enumerate(inputs, start=1):
        out = os.path.join(base, f"baby_cutout_{i}.png")
        remove_white_bg(inp, out)
        print(f"Saved {out}")
