"""Decode the four hexadecimal rows from diagnostic build D1 (no hardware access)."""
import argparse
import json

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('rows', nargs=4, help='Rows 0, 1, 2, 3, each eight hex digits')
a = p.parse_args()
d, c, w, f = [int(v.removeprefix('0x'), 16) for v in a.rows]
if any(v < 0 or v > 0xffffffff for v in (d, c, w, f)) or d >> 24 != 0xd1:
    p.error('Expected 32-bit values, with row 0 starting D1')
bits = lambda value, names: {name: bool(value & (1 << i)) for i, name in enumerate(names)}
report = {
    'build': 'V12 diagnostic D1; not a hardware-verified black-screen fix',
    'sensor_and_initialization': bits(d, ['ddr_cal_pass', 'ddr_cal_done', 'i2c_sequence_done',
        'i2c_nack_ever_seen', 'camera_nonzero_data_ever_seen', 'camera_de_ever_seen',
        'camera_vsync_edge_ever_seen', 'camera_clock_recently_responding']),
    'store': bits(d >> 8, ['read_error', 'bus_error', 'write_fifo_empty', 'write_fifo_busy',
        'read_fifo_reset', 'write_fifo_reset', 'read_valid', 'latest_valid']),
    'capture': bits(d >> 16, ['stop_capture', 'frame_boundary_seen', 'write_fifo_full',
        'write_fifo_busy', 'writer_reset', 'capture_armed', 'last_admitted_frame_bad',
        'last_admitted_frame_good']),
    'camera_eof_count_mod256': c >> 24,
    'last_sensor_frame_bytes': c & 0xffffff,
    'expected_sensor_frame_bytes': 1920 * 1080 * 2,
    'writer_state': ['IDLE', 'ADDR', 'DATA', 'RESP', 'RESET', 'INVALID', 'INVALID', 'INVALID'][w >> 29],
    'reader_state': ['IDLE', 'ADDR', 'DATA', 'RESET', 'RELEASE', 'DRAIN', 'INVALID', 'INVALID'][(w >> 26) & 7],
    'end_pending': bool(w & (1 << 25)),
    'end_good': bool(w & (1 << 24)),
    'write_failed': bool(w & (1 << 23)),
    'bus_error': bool(w & (1 << 22)),
    'write_offset_bytes': w & 0x3fffff,
    'ddr_committed_original_frames': f,
}
print(json.dumps(report, indent=2))
