import os
import sys
import cv2
import numpy as np


def remove_background(rgb, threshold=30, feather=15, shadow_darkness=0.92):
    """
    Remove a near-solid background including soft shadows.

    - rgb: HxWx3 float32 RGB image
    - threshold: color distance below which a pixel is fully background
    - feather: width of the alpha transition band
    - shadow_darkness: pixels darker than background * this factor are also treated as shadow
    """
    h, w = rgb.shape[:2]

    # Sample background color from the outer border (top/bottom/left/right strips)
    # Use KMeans to cluster border colors and pick the brightest cluster as background.
    border_width = 7
    top = rgb[0:border_width, :].reshape(-1, 3)
    bottom = rgb[h - border_width:h, :].reshape(-1, 3)
    left = rgb[:, 0:border_width].reshape(-1, 3)
    right = rgb[:, w - border_width:w].reshape(-1, 3)
    border = np.vstack([top, bottom, left, right])

    # KMeans with 2 clusters; the brighter one is the true background
    from sklearn.cluster import KMeans
    kmeans = KMeans(n_clusters=2, random_state=0, n_init=5)
    kmeans.fit(border)
    centers = kmeans.cluster_centers_
    brightness = centers.mean(axis=1)
    bg_color = centers[np.argmax(brightness)]
    # Clamp to white-ish to avoid drift into light grays
    bg_color = np.clip(bg_color, 245, 255)
    bg_gray = bg_color.mean()

    # Color distance to background
    dist = np.linalg.norm(rgb - bg_color, axis=2)

    # Brightness / luminance (approximate)
    luminance = rgb.mean(axis=2)

    # Saturation: low for gray backgrounds, high for colorful clothes/skin
    saturation = rgb.max(axis=2) - rgb.min(axis=2)

    # Background mask: bright, desaturated, and close to detected background color
    bg_mask = (
        (luminance > (bg_gray * 0.92))
        & (saturation < 55)
        & (dist < threshold * 3.0)
    )

    # Shadow mask: darker but still desaturated and close to background
    shadow_mask = (
        (luminance <= (bg_gray * 0.92))
        & (saturation < 55)
        & (dist < threshold * 4.0)
    )

    # Foreground: anything not background or shadow
    fg_mask = ~(bg_mask | shadow_mask)

    # Build smooth alpha channel from color distance
    alpha = np.clip((dist - (threshold - feather)) / feather * 255.0, 0.0, 255.0)
    alpha[bg_mask | shadow_mask] = 0.0
    alpha = alpha.astype(np.uint8)

    return alpha, bg_color


def clean_alpha(alpha, min_blob_size=500):
    """Keep only the largest foreground blob and smooth its edges."""
    # Binary mask
    _, binary = cv2.threshold(alpha, 10, 255, cv2.THRESH_BINARY)

    # Open first to break thin shadows connecting to the feet/hands
    kernel = np.ones((3, 3), np.uint8)
    binary = cv2.morphologyEx(binary, cv2.MORPH_OPEN, kernel, iterations=1)

    # Close small gaps (e.g. between head and body)
    close_kernel = np.ones((5, 5), np.uint8)
    binary = cv2.morphologyEx(binary, cv2.MORPH_CLOSE, close_kernel, iterations=2)

    # Keep only the largest connected component (the baby)
    num_labels, labels, stats, _ = cv2.connectedComponentsWithStats(binary, connectivity=8)
    if num_labels > 1:
        largest = 1 + np.argmax(stats[1:, cv2.CC_STAT_AREA])
        binary = (labels == largest).astype(np.uint8) * 255

    # Feather edge inward to remove remaining halo/shadow
    erode_kernel = np.ones((3, 3), np.uint8)
    binary = cv2.erode(binary, erode_kernel, iterations=2)

    # Smooth edge
    binary = cv2.GaussianBlur(binary, (5, 5), 0)

    # Combine cleaned mask with the original feathered alpha
    alpha = (alpha.astype(np.float32) * binary.astype(np.float32) / 255.0).astype(np.uint8)

    return alpha


def extract_transparent_frames(video_path, out_dir, target_fps=12, threshold=30, feather=15, target_width=360):
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        print(f"Cannot open video: {video_path}", file=sys.stderr)
        return

    orig_fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    interval = max(1, int(round(orig_fps / target_fps)))

    os.makedirs(out_dir, exist_ok=True)

    frame_idx = 0
    out_idx = 0
    while True:
        ret, frame = cap.read()
        if not ret:
            break

        if frame_idx % interval != 0:
            frame_idx += 1
            continue

        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB).astype(np.float32)

        alpha, _ = remove_background(rgb, threshold=threshold, feather=feather)
        alpha = clean_alpha(alpha)

        # Resize if needed
        if target_width and rgb.shape[1] > target_width:
            scale = target_width / rgb.shape[1]
            target_height = int(round(rgb.shape[0] * scale))
            rgb = cv2.resize(rgb, (target_width, target_height), interpolation=cv2.INTER_AREA)
            alpha = cv2.resize(alpha, (target_width, target_height), interpolation=cv2.INTER_AREA)

        rgba = np.dstack((rgb.astype(np.uint8), alpha))
        out_path = os.path.join(out_dir, f"frame_{out_idx:04d}.png")
        cv2.imwrite(out_path, cv2.cvtColor(rgba, cv2.COLOR_RGBA2BGRA))

        out_idx += 1
        frame_idx += 1

    cap.release()
    print(f"Extracted {out_idx} transparent frames to {out_dir}")


def process_static_image(image_path, out_path, threshold=30, feather=15):
    """Remove background from a static RGB/RGBA image."""
    img = Image.open(image_path).convert('RGB')
    rgb = np.array(img, dtype=np.float32)

    alpha, _ = remove_background(rgb, threshold=threshold, feather=feather)
    alpha = clean_alpha(alpha, min_blob_size=100)

    rgba = np.dstack((rgb.astype(np.uint8), alpha))
    out = Image.fromarray(rgba, 'RGBA')
    bbox = out.getbbox()
    if bbox:
        out = out.crop(bbox)
    out.save(out_path)
    print(f"Saved transparent static image to {out_path}, size {out.size}")


if __name__ == "__main__":
    from PIL import Image

    base = "/Users/shmiyangkuan/WorkBuddy/2026-08-17-13-59-18/output"

    # Re-process the static idle image
    process_static_image(
        os.path.join(base, "A_cute_3D_rendered_baby_charac_2026-08-17T06-45-26.png"),
        os.path.join(base, "baby_character_transparent.png"),
        threshold=25,
        feather=12,
    )

    # Extract action frames
    videos = [
        ("baby_crawl.mp4", "frames_crawl"),
        ("baby_walk.mp4", "frames_walk"),
        ("baby_stroll.mp4", "frames_stroll"),
    ]
    for vid, folder in videos:
        extract_transparent_frames(
            os.path.join(base, vid),
            os.path.join(base, folder),
            target_fps=12,
            threshold=30,
            feather=15,
        )
