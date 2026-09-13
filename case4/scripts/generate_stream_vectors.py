"""Independent regression oracle; it does not call the project's Golden functions.

Generates stimulus and expected transactions for four current DUT variants.
Reset flush timing is modeled at the public input/output boundary.
"""
from pathlib import Path
import json
import sys
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
VECTORS = ROOT / 'build/stream_vectors'
VECTORS.mkdir(parents=True, exist_ok=True)


def expected_image(pixels, fmt, median):
    values = pixels.astype(np.int32)
    if fmt == 0:
        r5, g6, b5 = values >> 11 & 31, values >> 5 & 63, values & 31
        r, g, b = (r5 << 3) | (r5 >> 2), (g6 << 2) | (g6 >> 4), (b5 << 3) | (b5 >> 2)
    else:
        r, g, b = values >> 16 & 255, values >> 8 & 255, values & 255
    gray = (77 * r + 150 * g + 29 * b + 128) // 256
    radius = 1
    filtered = gray
    if median:
        windows = np.lib.stride_tricks.sliding_window_view(gray, (3, 3))
        filtered = np.partition(windows.reshape(*windows.shape[:2], 9), 4, axis=-1)[..., 4]
        radius = 2
    # Direct matrix convolution, deliberately independent of RTL partial sums.
    win = np.lib.stride_tricks.sliding_window_view(filtered, (3, 3))
    kx = np.array([[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]])
    ky = kx.T
    gx = np.einsum('yxij,ij->yx', win, kx)
    gy = np.einsum('yxij,ij->yx', win, ky)
    mag = abs(gx) + abs(gy)
    return radius, gx, gy, mag


def pack_expected(x, y, gx, gy, mag, flags):
    return (flags << 56) | (x << 46) | (y << 36) | ((int(gx) & 4095) << 24) | ((int(gy) & 4095) << 12) | (int(mag) << 1)


def make_case(name, width, height, fmt, frames, seed, image_path=None):
    rng = np.random.default_rng(seed)
    cycles = []
    expected = [[] for _ in range(4)]
    due = [[] for _ in range(4)]
    # Number of edges after the edge accepting the final source pixel.
    # gray + window + [median + window] + three Sobel regs + threshold.
    latency = [5, 6, 9, 11]  # default three-stage median; old one-stage was 7/9

    def emit(rst=0, valid=0, x=0, y=0, pixel=0, flags=0, threshold=320):
        cycle = len(cycles)
        if rst:
            for queue in due:
                queue[:] = [item for item in queue if item[0] < cycle]
        packed = (rst << 59) | (valid << 58) | (flags << 55) | (x << 45) | (y << 35) | (int(pixel) << 11) | threshold
        cycles.append(packed)

    def frame(pixels, mode, partial=None):
        refs = [expected_image(pixels, fmt, m) for m in (False, True)]
        stop = width * height if partial is None else partial
        for idx in range(stop):
            y, x = divmod(idx, width)
            if mode == 'bubbles' and rng.integers(0, 4) == 0:
                for _ in range(int(rng.integers(1, 5))):
                    # Invalid-cycle coordinates, payload and markers are intentionally dirty.
                    emit(x=1023, y=1023, pixel=0xFFFFFF, flags=7, threshold=int(rng.integers(0, 2048)))
            flags = ((x == 0 and y == 0) << 2) | ((x == width-1) << 1) | (x == width-1 and y == height-1)
            threshold = [0, 1, 100, 320, 1020, 1530, 1531, 2047][(x + 3*y) % 8]
            tick = len(cycles)
            emit(valid=1, x=x, y=y, pixel=pixels[y, x], flags=flags, threshold=threshold)
            for variant in range(4):
                radius, gx, gy, mag = refs[variant//2]
                if x >= 2*radius and y >= 2*radius:
                    cx, cy = x-radius, y-radius
                    oflags = 8 | ((x == 2*radius and y == 2*radius) << 2) | ((x == width-1) << 1) | (x == width-1 and y == height-1)
                    value = pack_expected(cx, cy, gx[y-2*radius, x-2*radius], gy[y-2*radius, x-2*radius], mag[y-2*radius, x-2*radius], oflags)
                    due[variant].append((tick+latency[variant], value))

    for _ in range(4):
        emit(rst=1)
    for index in range(frames):
        pixels = rng.integers(0, 1 << (16 if fmt == 0 else 24), (height, width), dtype=np.uint32)
        if image_path:
            rgb = np.asarray(Image.open(image_path).convert('RGB'), dtype=np.uint32)
            if fmt == 0:
                pixels = ((rgb[..., 0] >> 3) << 11) | ((rgb[..., 1] >> 2) << 5) | (rgb[..., 2] >> 3)
            else:
                pixels = (rgb[..., 0] << 16) | (rgb[..., 1] << 8) | rgb[..., 2]
        elif index == 1:
            pixels.fill((1 << (16 if fmt == 0 else 24))-1)
        elif index == 2:
            pixels.fill(0)
        frame(pixels, 'bubbles' if index % 3 == 2 else 'continuous')
    # Abort an active partial frame with a synchronous reset, then start a new
    # complete frame. Includes pending results in both neighborhood pipelines.
    if not image_path:
        pixels = rng.integers(0, 1 << (16 if fmt == 0 else 24), (height, width), dtype=np.uint32)
        frame(pixels, 'continuous', partial=max(1, width*height-2))
        emit(rst=1)
        emit(rst=1)
        frame(pixels, 'bubbles')
    for _ in range(32):
        emit()
    for variant in range(4):
        expected[variant] = due[variant]
    prefix = VECTORS / name
    prefix.mkdir(exist_ok=True)
    with (prefix/'input.hex').open('w') as out:
        out.writelines(f'{v:015x}\n' for v in cycles)
    for i, queue in enumerate(expected):
        with (prefix/f'expected{i}.hex').open('w') as out:
            # Upper 36 bits encode the exact expected output cycle.
            out.writelines(f'{((tick << 60) | val):024x}\n' for tick, val in queue)
    metadata = dict(name=name, width=width, height=height, fmt=fmt, cycles=len(cycles), expected=[len(q) for q in expected], seed=seed, source=str(image_path) if image_path else 'deterministic NumPy random/full-white/full-black')
    (prefix/'metadata.json').write_text(json.dumps(metadata, indent=2))
    print(json.dumps(metadata))
    return metadata


if __name__ == '__main__':
    configs = []
    for w, h in [(5, 5), (7, 9), (8, 6), (17, 13), (640, 480)]:
        for fmt in [0, 1]:
            configs.append(make_case(f'w{w}_h{h}_f{fmt}', w, h, fmt, 3, 20260913+w+fmt))
    peppers = ROOT / 'images/peppers.png'
    if peppers.exists():
        for fmt in [0, 1]:
            configs.append(make_case(f'peppers_f{fmt}', 512, 512, fmt, 1, 20260913, peppers))
    (VECTORS/'manifest.json').write_text(json.dumps(configs, indent=2))
