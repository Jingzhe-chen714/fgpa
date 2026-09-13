"""Python Golden Model for case 4 real-time edge detection.

The implementation intentionally mirrors an RTL-friendly stream:
8-bit pixels, a 3x3 window, integer Sobel arithmetic, explicit border policy,
and row-major HEX vectors for later $readmemh-based verification.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Dict, Iterable, Tuple

import numpy as np
from PIL import Image


GRAY_COEFFS = (77, 150, 29)  # BT.601 approximation, denominator 256
SOBEL_GX = np.array([[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]], dtype=np.int16)
SOBEL_GY = np.array([[-1, -2, -1], [0, 0, 0], [1, 2, 1]], dtype=np.int16)


def load_image(path: Path) -> np.ndarray:
    """Load an image as HxWx3 uint8 RGB or HxW uint8 grayscale."""
    with Image.open(path) as im:
        if im.mode in ("1", "L", "I", "F"):
            return np.asarray(im.convert("L"), dtype=np.uint8)
        return np.asarray(im.convert("RGB"), dtype=np.uint8)


def ensure_rgb(image: np.ndarray) -> np.ndarray:
    if image.ndim == 2:
        return np.repeat(image[..., None], 3, axis=2)
    if image.ndim == 3 and image.shape[2] == 3:
        return image
    raise ValueError(f"expected HxW or HxWx3 image, got {image.shape}")


def gray_bt601_float(rgb: np.ndarray) -> np.ndarray:
    """Floating reference, rounded to nearest integer."""
    rgb = ensure_rgb(rgb).astype(np.float32)
    y = np.rint(0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2])
    return np.clip(y, 0, 255).astype(np.uint8)


def gray_bt601_acc(rgb: np.ndarray) -> np.ndarray:
    """Return the widened integer accumulator before the >>8 operation."""
    rgb = ensure_rgb(rgb).astype(np.uint32)
    return (
        GRAY_COEFFS[0] * rgb[..., 0]
        + GRAY_COEFFS[1] * rgb[..., 1]
        + GRAY_COEFFS[2] * rgb[..., 2]
    ).astype(np.uint32)


def gray_bt601_fixed(rgb: np.ndarray) -> np.ndarray:
    """RTL-friendly integer implementation: (77R+150G+29B+128)>>8."""
    acc = gray_bt601_acc(rgb) + 128
    return np.right_shift(acc, 8).clip(0, 255).astype(np.uint8)


def pad3(image: np.ndarray, border: str) -> np.ndarray:
    if border == "zero":
        return np.pad(image, ((1, 1), (1, 1)), mode="constant", constant_values=0)
    if border == "replicate":
        return np.pad(image, ((1, 1), (1, 1)), mode="edge")
    if border == "reflect":
        return np.pad(image, ((1, 1), (1, 1)), mode="reflect")
    raise ValueError("border must be zero, replicate, or reflect")


def windows3(image: np.ndarray, border: str) -> np.ndarray:
    """Return HxWx3x3 windows without changing the input dtype."""
    padded = pad3(image, border)
    rows = []
    for dy in range(3):
        for dx in range(3):
            rows.append(padded[dy : dy + image.shape[0], dx : dx + image.shape[1]])
    return np.stack(rows, axis=-1).reshape(image.shape[0], image.shape[1], 3, 3)


def median3x3(image: np.ndarray, border: str = "replicate", force_zero_border: bool = False) -> np.ndarray:
    """3x3 median filter using a sorting operation equivalent to a comparator network."""
    image = np.asarray(image, dtype=np.uint8)
    win = windows3(image, border).reshape(image.shape[0], image.shape[1], 9)
    result = np.sort(win, axis=-1)[..., 4].astype(np.uint8)
    if force_zero_border:
        result[[0, -1], :] = 0
        result[:, [0, -1]] = 0
    return result


def interior_mask(shape: Tuple[int, int], radius: int) -> np.ndarray:
    """Pixels whose complete radius-sized neighborhood is inside the frame."""
    h, w = shape
    mask = np.zeros((h, w), dtype=bool)
    if h > 2 * radius and w > 2 * radius:
        mask[radius : h - radius, radius : w - radius] = True
    return mask


def sobel_partials(image: np.ndarray, border: str = "zero") -> Dict[str, np.ndarray]:
    """Return the six signed partial sums used by an RTL-friendly Sobel pipeline."""
    image = np.asarray(image, dtype=np.int16)
    win = windows3(image, border).astype(np.int32)
    p00, p01, p02 = win[..., 0, 0], win[..., 0, 1], win[..., 0, 2]
    p10, p11, p12 = win[..., 1, 0], win[..., 1, 1], win[..., 1, 2]
    p20, p21, p22 = win[..., 2, 0], win[..., 2, 1], win[..., 2, 2]
    return {
        "gx_top": p02 - p00,
        "gx_mid": 2 * (p12 - p10),
        "gx_bottom": p22 - p20,
        "gy_top": p20 - p00,
        "gy_mid": 2 * (p21 - p01),
        "gy_bottom": p22 - p02,
    }


def sobel_gradients(
    image: np.ndarray,
    border: str = "zero",
    force_zero_border: bool = True,
    valid_mask: np.ndarray | None = None,
) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Return signed Gx, signed Gy and L1 magnitude.

    Gx/Gy are int16 (their mathematical range is -1020..1020); magnitude is
    int32 so the comparison domain remains explicit and lossless.
    """
    partials = sobel_partials(image, border)
    gx = partials["gx_top"] + partials["gx_mid"] + partials["gx_bottom"]
    gy = partials["gy_top"] + partials["gy_mid"] + partials["gy_bottom"]
    magnitude = np.abs(gx) + np.abs(gy)
    if force_zero_border and valid_mask is None:
        for arr in (gx, gy, magnitude):
            arr[[0, -1], :] = 0
            arr[:, [0, -1]] = 0
    if valid_mask is not None:
        for arr in (gx, gy, magnitude):
            arr[~valid_mask] = 0
    return gx.astype(np.int16), gy.astype(np.int16), magnitude.astype(np.int32)


def threshold_edges(magnitude: np.ndarray, threshold: int) -> np.ndarray:
    if not 0 <= threshold <= 2047:
        raise ValueError("Sobel L1 threshold must be in unsigned 11-bit range 0..2047")
    return np.where(magnitude >= threshold, 255, 0).astype(np.uint8)


def overlay_edges(rgb: np.ndarray, edge: np.ndarray, color=(255, 0, 0)) -> np.ndarray:
    out = ensure_rgb(rgb).copy()
    out[edge > 0] = np.asarray(color, dtype=np.uint8)
    return out


def array_metrics(a: np.ndarray, b: np.ndarray) -> Dict[str, float]:
    a = np.asarray(a).astype(np.int64)
    b = np.asarray(b).astype(np.int64)
    diff = np.abs(a - b)
    mse = float(np.mean((a - b) ** 2))
    psnr = float("inf") if mse == 0 else float(10.0 * np.log10((255.0**2) / mse))
    return {
        "max_abs": int(diff.max(initial=0)),
        "mae": float(diff.mean()),
        "exact_fraction": float(np.mean(diff == 0)),
        "psnr_db_8bit": psnr,
    }


def save_u8(path: Path, array: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.asarray(array, dtype=np.uint8), mode="L").save(path)


def save_rgb(path: Path, array: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(ensure_rgb(np.asarray(array, dtype=np.uint8)), mode="RGB").save(path)


def write_hex(path: Path, array: np.ndarray, width: int, signed: bool = False) -> None:
    """Write one row-major value per line for a future Verilog $readmemh."""
    flat = np.asarray(array).reshape(-1).astype(np.int64)
    mask = (1 << width) - 1
    with path.open("w", encoding="ascii", newline="\n") as f:
        for value in flat:
            if signed:
                value &= mask
            f.write(f"{int(value) & mask:0{(width + 3) // 4}X}\n")


def synthetic_patterns() -> Dict[str, np.ndarray]:
    """Small deterministic patterns for window/border regression."""
    h = w = 128
    yy, xx = np.indices((h, w))
    checker = (((xx // 8 + yy // 8) & 1) * 255).astype(np.uint8)
    ramp = np.tile(np.linspace(0, 255, w, dtype=np.uint8), (h, 1))
    impulse = np.zeros((h, w), dtype=np.uint8)
    impulse[h // 2, w // 2] = 255
    square = np.zeros((h, w), dtype=np.uint8)
    square[32:96, 32:96] = 255
    return {"checkerboard": checker, "ramp": ramp, "impulse": impulse, "square": square}


def run_pipeline(
    image: np.ndarray,
    threshold: int,
    use_median: bool,
    sobel_border: str = "zero",
    median_border: str = "replicate",
) -> Dict[str, np.ndarray]:
    rgb = ensure_rgb(image)
    gray_float = gray_bt601_float(rgb)
    gray_acc = gray_bt601_acc(rgb)
    gray_fixed = gray_bt601_fixed(rgb)
    if use_median:
        filtered = median3x3(gray_fixed, border=median_border, force_zero_border=True)
        valid_mask = interior_mask(gray_fixed.shape, radius=2)
    else:
        filtered = gray_fixed
        valid_mask = interior_mask(gray_fixed.shape, radius=1)
    gx, gy, magnitude = sobel_gradients(
        filtered,
        border=sobel_border,
        force_zero_border=not use_median,
        valid_mask=valid_mask,
    )
    edge = threshold_edges(magnitude, threshold)
    # Zero magnitude does not encode window validity: at T=0 even a zero
    # compares true. Preserve INVALID borders and the original overlay RGB.
    edge[~valid_mask] = 0
    return {
        "rgb": rgb,
        "gray_float": gray_float,
        "gray_acc": gray_acc,
        "gray_fixed": gray_fixed,
        "filtered": filtered,
        "window9": windows3(filtered, sobel_border).reshape(filtered.shape[0], filtered.shape[1], 9),
        "valid_mask": valid_mask,
        "gx": gx,
        "gy": gy,
        "magnitude": magnitude,
        "magnitude_u8": np.clip(magnitude, 0, 255).astype(np.uint8),
        "edge": edge,
        "overlay": overlay_edges(rgb, edge),
    }


def save_pipeline(results: Dict[str, np.ndarray], output_dir: Path, threshold: int, use_median: bool, input_path: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    save_rgb(output_dir / "input_rgb.png", results["rgb"])
    save_u8(output_dir / "gray_float.png", results["gray_float"])
    save_u8(output_dir / "gray_fixed.png", results["gray_fixed"])
    save_u8(output_dir / "valid_mask.png", results["valid_mask"].astype(np.uint8) * 255)
    save_u8(output_dir / "gray_diff_x10.png", np.clip(np.abs(results["gray_float"].astype(np.int16) - results["gray_fixed"].astype(np.int16)) * 10, 0, 255))
    save_u8(output_dir / "filtered.png", results["filtered"])
    save_u8(output_dir / "magnitude.png", results["magnitude_u8"])
    save_u8(output_dir / "edge.png", results["edge"])
    save_rgb(output_dir / "overlay.png", results["overlay"])

    np.save(output_dir / "gx.npy", results["gx"])
    np.save(output_dir / "gy.npy", results["gy"])
    np.save(output_dir / "magnitude.npy", results["magnitude"])
    np.save(output_dir / "gray_acc.npy", results["gray_acc"])
    np.save(output_dir / "window9.npy", results["window9"])
    np.save(output_dir / "valid_mask.npy", results["valid_mask"])
    write_hex(output_dir / "gray_fixed.hex", results["gray_fixed"], 8)
    write_hex(output_dir / "gray_acc_u17.hex", results["gray_acc"], 17)
    write_hex(output_dir / "filtered.hex", results["filtered"], 8)
    write_hex(output_dir / "gx_s16.hex", results["gx"], 16, signed=True)
    write_hex(output_dir / "gy_s16.hex", results["gy"], 16, signed=True)
    write_hex(output_dir / "magnitude_u11.hex", results["magnitude"], 11)
    write_hex(output_dir / "edge.hex", results["edge"], 8)
    write_hex(output_dir / "valid_mask.hex", results["valid_mask"].astype(np.uint8), 1)

    gray_metrics = array_metrics(results["gray_float"], results["gray_fixed"])
    metadata = {
        "input": str(input_path),
        "shape": list(results["gray_fixed"].shape),
        "threshold": threshold,
        "median": use_median,
        "gray_coeffs": list(GRAY_COEFFS),
        "gray_denominator": 256,
        "sobel_magnitude": "abs(Gx)+abs(Gy)",
        "gray_float_vs_fixed": gray_metrics,
        "valid_pixels": int(np.count_nonzero(results["valid_mask"])),
        "edge_density": float(np.mean(results["edge"] > 0)),
        "edge_pixels": int(np.count_nonzero(results["edge"])),
    }
    (output_dir / "metrics.json").write_text(json.dumps(metadata, indent=2, ensure_ascii=False), encoding="utf-8")


def run_one(input_path: Path, output_dir: Path, threshold: int, use_median: bool) -> None:
    image = load_image(input_path)
    results = run_pipeline(image, threshold=threshold, use_median=use_median)
    save_pipeline(results, output_dir, threshold, use_median, input_path)
    print(json.dumps({
        "input": str(input_path),
        "output": str(output_dir),
        "shape": list(results["gray_fixed"].shape),
        "gray_metrics": array_metrics(results["gray_float"], results["gray_fixed"]),
        "edge_density": float(np.mean(results["edge"] > 0)),
    }, ensure_ascii=False))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, help="input image")
    parser.add_argument("--output-dir", type=Path, help="directory for outputs")
    parser.add_argument("--threshold", type=int, default=320, help="Sobel L1 threshold, 0..2047")
    parser.add_argument("--median", action="store_true", help="enable 3x3 median filter")
    parser.add_argument("--patterns-dir", type=Path, help="also generate synthetic regression patterns")
    args = parser.parse_args()

    if args.patterns_dir:
        args.patterns_dir.mkdir(parents=True, exist_ok=True)
        for name, pattern in synthetic_patterns().items():
            save_u8(args.patterns_dir / f"{name}.png", pattern)
            result = run_pipeline(pattern, threshold=args.threshold, use_median=args.median)
            save_pipeline(result, args.patterns_dir / name / "pipeline", args.threshold, args.median, Path(f"{name}.png"))

    if args.input is None:
        if args.patterns_dir:
            return
        parser.error("--input is required unless --patterns-dir is used")
    if args.output_dir is None:
        parser.error("--output-dir is required with --input")
    run_one(args.input, args.output_dir, args.threshold, args.median)


if __name__ == "__main__":
    main()
