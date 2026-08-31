"""Small deterministic sanity suite; no pytest dependency is required."""

from pathlib import Path
import sys

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from golden_edge import (  # noqa: E402
    gray_bt601_fixed,
    median3x3,
    run_pipeline,
    sobel_gradients,
    sobel_partials,
    threshold_edges,
)


def test_gray_extremes() -> None:
    black = np.zeros((2, 2, 3), dtype=np.uint8)
    white = np.full((2, 2, 3), 255, dtype=np.uint8)
    assert np.all(gray_bt601_fixed(black) == 0)
    assert np.all(gray_bt601_fixed(white) == 255)


def test_sobel_step_sign_and_scale() -> None:
    vertical = np.zeros((5, 5), dtype=np.uint8)
    vertical[:, 3:] = 255
    gx, gy, mag = sobel_gradients(vertical)
    assert (int(gx[2, 2]), int(gy[2, 2]), int(mag[2, 2])) == (1020, 0, 1020)

    horizontal = np.zeros((5, 5), dtype=np.uint8)
    horizontal[3:, :] = 255
    gx, gy, mag = sobel_gradients(horizontal)
    assert (int(gx[2, 2]), int(gy[2, 2]), int(mag[2, 2])) == (0, 1020, 1020)


def test_sobel_partials_reconstruct() -> None:
    rng = np.random.default_rng(20260823)
    image = rng.integers(0, 256, (32, 37), dtype=np.uint8)
    p = sobel_partials(image)
    gx, gy, _ = sobel_gradients(image)
    assert np.array_equal((p["gx_top"] + p["gx_mid"] + p["gx_bottom"])[1:-1, 1:-1], gx[1:-1, 1:-1])
    assert np.array_equal((p["gy_top"] + p["gy_mid"] + p["gy_bottom"])[1:-1, 1:-1], gy[1:-1, 1:-1])


def test_median_known_values() -> None:
    image = np.full((5, 5), 10, dtype=np.uint8)
    image[2, 2] = 255
    filtered = median3x3(image, border="replicate", force_zero_border=False)
    assert int(filtered[2, 2]) == 10


def test_threshold_monotonicity_and_valid_area() -> None:
    rng = np.random.default_rng(7)
    image = rng.integers(0, 256, (32, 32), dtype=np.uint8)
    _, _, mag = sobel_gradients(image)
    assert np.count_nonzero(threshold_edges(mag, 100)) >= np.count_nonzero(threshold_edges(mag, 500))
    one = run_pipeline(image, threshold=320, use_median=False)
    two = run_pipeline(image, threshold=320, use_median=True)
    assert int(one["valid_mask"].sum()) == (32 - 2) * (32 - 2)
    assert int(two["valid_mask"].sum()) == (32 - 4) * (32 - 4)


def main() -> None:
    tests = [value for name, value in globals().items() if name.startswith("test_")]
    for test in tests:
        test()
        print(f"PASS {test.__name__}")
    print(f"{len(tests)} Golden tests passed")


if __name__ == "__main__":
    main()
