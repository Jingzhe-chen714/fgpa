"""Exhaustive fixed-point gray conversion check for the contest pixel formats.

The contest description does not mandate one sensor packing, so this checker
covers both the usual RGB565 camera output and RGB888.  The reference is the
BT.601 real-valued luminance, while the hardware result is the rounded Q8
formula used by the RTL::

    Y = (77*R + 150*G + 29*B + 128) >> 8

The reported ``max_continuous_error`` is measured before rounding.  A value
below one output-code LSB is the relevant quantization guarantee.  We also
report the stricter comparison against a rounded floating reference; that
comparison may differ by one code because two independently rounded values can
land on opposite sides of a half-code boundary.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np


COEFFS = (77, 150, 29)
DEN = 256


def expand_rgb565(word: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    word = np.asarray(word, dtype=np.uint32)
    r5 = (word >> 11) & 0x1F
    g6 = (word >> 5) & 0x3F
    b5 = word & 0x1F
    # Bit replication is the conventional full-range RGB565 -> RGB888 map.
    r8 = (r5 << 3) | (r5 >> 2)
    g8 = (g6 << 2) | (g6 >> 4)
    b8 = (b5 << 3) | (b5 >> 2)
    return r8.astype(np.uint16), g8.astype(np.uint16), b8.astype(np.uint16)


def fixed_gray(r: np.ndarray, g: np.ndarray, b: np.ndarray) -> np.ndarray:
    acc = COEFFS[0] * r.astype(np.uint32)
    acc += COEFFS[1] * g.astype(np.uint32)
    acc += COEFFS[2] * b.astype(np.uint32)
    return ((acc + DEN // 2) >> 8).astype(np.int32)


def check_format(name: str, r: np.ndarray, g: np.ndarray, b: np.ndarray) -> dict[str, float | int | str]:
    real = 0.299 * r + 0.587 * g + 0.114 * b
    fixed = fixed_gray(r, g, b)
    continuous = np.abs(fixed - real)
    rounded = np.rint(real).astype(np.int32)
    code_error = np.abs(fixed - rounded)
    return {
        "format": name,
        "samples": int(r.size),
        "max_continuous_error_lsb": float(continuous.max(initial=0.0)),
        "mae_continuous_lsb": float(continuous.mean()),
        "max_rounded_code_difference": int(code_error.max(initial=0)),
        "rounded_mismatch_count": int(np.count_nonzero(code_error)),
        "pass_continuous_lt_1_lsb": bool(continuous.max(initial=0.0) < 1.0),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", type=Path, help="optional JSON report path")
    args = parser.parse_args()

    rgb565_words = np.arange(1 << 16, dtype=np.uint32)
    r565, g565, b565 = expand_rgb565(rgb565_words)
    reports = [check_format("RGB565 expanded to RGB888", r565, g565, b565)]

    # RGB888 is too large for a naive 16.7M-entry materialization in some
    # development environments, so enumerate each channel independently in
    # chunks while retaining an exact exhaustive maximum.
    max_err = 0.0
    mae_sum = 0.0
    samples = 0
    max_code_diff = 0
    mismatch = 0
    levels = np.arange(256, dtype=np.int32)
    for r in levels:
        rr = np.full(256 * 256, r, dtype=np.int32)
        gg = np.repeat(levels, 256)
        bb = np.tile(levels, 256)
        real = 0.299 * rr + 0.587 * gg + 0.114 * bb
        fixed = fixed_gray(rr, gg, bb)
        diff = np.abs(fixed - real)
        code_diff = np.abs(fixed - np.rint(real).astype(np.int32))
        max_err = max(max_err, float(diff.max(initial=0.0)))
        mae_sum += float(diff.sum())
        samples += int(diff.size)
        max_code_diff = max(max_code_diff, int(code_diff.max(initial=0)))
        mismatch += int(np.count_nonzero(code_diff))
    reports.append(
        {
            "format": "RGB888",
            "samples": samples,
            "max_continuous_error_lsb": max_err,
            "mae_continuous_lsb": mae_sum / samples,
            "max_rounded_code_difference": max_code_diff,
            "rounded_mismatch_count": mismatch,
            "pass_continuous_lt_1_lsb": bool(max_err < 1.0),
        }
    )

    for report in reports:
        print(report)
    if not all(report["pass_continuous_lt_1_lsb"] for report in reports):
        raise SystemExit("fixed-point gray conversion exceeds 1 LSB")
    if args.json:
        import json

        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(reports, indent=2), encoding="utf-8")
    print("Fixed gray conversion: PASS (continuous quantization error < 1 LSB)")


if __name__ == "__main__":
    main()
