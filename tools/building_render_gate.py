"""Compare registered original-camera pictures outside a source-derived mask."""

from pathlib import Path
import numpy as np
from PIL import Image


def lanczos_support(native_mask: Path, size=(600, 400)) -> Image.Image:
    """Union of the actual Godot 4.6.1 Lanczos-3 sampling windows.

    A resized white mask can cancel to black through negative filter weights.
    Propagate Boolean support instead. Bounds follow core/io/image.cpp in the
    official 4.6.1-stable tag; this mask never inspects a before/after diff.
    """
    rgb = np.asarray(Image.open(native_mask).convert("RGB"))
    if not np.all(rgb == rgb[:, :, :1]):
        raise ValueError("native source mask contains coloured scenery")
    source = rgb[:, :, 0] != 0
    height, width = source.shape
    out_width, out_height = size
    horizontal = np.zeros((height, out_width), bool)
    x_scale = np.float32(width / out_width)
    radius = int(np.float32(3) * max(x_scale, np.float32(1)))
    for x in range(out_width):
        centre = int(np.float32(x + 0.5) * x_scale)
        horizontal[:, x] = source[
            :, max(0, centre - radius + 1) : min(width, centre + radius + 1)
        ].any(axis=1)
    result = np.zeros((out_height, out_width), bool)
    y_scale = np.float32(height / out_height)
    radius = int(np.float32(3) * max(y_scale, np.float32(1)))
    for y in range(out_height):
        centre = int(np.float32(y + 0.5) * y_scale)
        result[y] = horizontal[
            max(0, centre - radius + 1) : min(height, centre + radius + 1)
        ].any(axis=0)
    return Image.fromarray(result.astype(np.uint8) * 255)


def compare(before: Path, after: Path, mask: Path) -> dict[str, int]:
    a = np.asarray(Image.open(before).convert("RGB"))
    b = np.asarray(Image.open(after).convert("RGB"))
    rgb = np.asarray(Image.open(mask).convert("RGB"))
    if not (a.shape == b.shape == rgb.shape):
        raise ValueError("render and mask dimensions differ")
    if not np.all(rgb == rgb[:, :, :1]):
        raise ValueError(
            "source mask contains coloured scenery; mask capture is invalid"
        )
    allowed = rgb[:, :, 0] != 0
    changed = np.any(a != b, axis=2)
    return {
        "changed": int(changed.sum()),
        "mask_pixels": int(allowed.sum()),
        "outside_mask": int((changed & ~allowed).sum()),
    }
