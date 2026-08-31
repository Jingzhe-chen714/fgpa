"""Generate a tiny Python-Golden vector set for the XSIM core scoreboard."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np

from golden_edge import run_pipeline, write_hex


def main() -> None:
    h, w = 6, 8
    yy, xx = np.indices((h, w))
    gray = ((17 * xx + 31 * yy + 7 * ((xx * yy) % 5) + 3) & 0xFF).astype(np.uint8)
    rgb = np.repeat(gray[..., None], 3, axis=2)
    result = run_pipeline(rgb, threshold=100, use_median=False)

    out = Path(__file__).resolve().parent / "tb" / "vectors"
    out.mkdir(parents=True, exist_ok=True)
    packed = (
        (rgb[..., 0].astype(np.uint32) << 16)
        | (rgb[..., 1].astype(np.uint32) << 8)
        | rgb[..., 2].astype(np.uint32)
    )
    write_hex(out / "small_input_rgb888.hex", packed, 24)
    write_hex(out / "small_gray_fixed.hex", result["gray_fixed"], 8)
    write_hex(out / "small_gx_s16.hex", result["gx"], 16, signed=True)
    write_hex(out / "small_gy_s16.hex", result["gy"], 16, signed=True)
    write_hex(out / "small_magnitude_u11.hex", result["magnitude"], 11)
    write_hex(out / "small_edge.hex", result["edge"] // 255, 1)
    (out / "metadata.json").write_text(
        json.dumps({"width": w, "height": h, "threshold": 100, "median": False}, indent=2),
        encoding="utf-8",
    )
    print(f"Generated Golden RTL vectors in {out}")


if __name__ == "__main__":
    main()
