"""Regression checks for the boardless tensor performance model."""

from __future__ import annotations

from tensor_perf_model import estimate_tensor_perf


def main() -> int:
    baseline = estimate_tensor_perf()
    assert baseline["stage_read_requests"] == 17_376_000
    assert baseline["stage_write_requests"] == 3_705_600
    assert baseline["logical_64bit_requests"] == 21_388_800
    assert baseline["bus_bytes_per_frame"] == 342_220_800
    assert baseline["memory_cycle_lower_bound"] == 85_555_200
    assert baseline["compute_cycle_lower_bound"] == 6_691_200
    assert not baseline["meets_frame_budget"]

    packed = estimate_tensor_perf(pack_factor=2, read_reuse=9,
                                  outstanding=16)
    assert packed["bus_beats_per_frame"] < baseline["bus_beats_per_frame"]
    assert packed["memory_cycle_lower_bound"] < baseline[
        "memory_cycle_lower_bound"
    ]
    assert packed["bus_bytes_per_frame"] < baseline["bus_bytes_per_frame"]

    for bad in (
        {"pack_factor": 0},
        {"read_reuse": 0},
        {"outstanding": 0},
        {"bus_bytes": 10},
    ):
        try:
            estimate_tensor_perf(**bad)
        except ValueError:
            pass
        else:
            raise AssertionError(f"invalid input accepted: {bad}")

    print(
        "C1_TENSOR_PERF_MODEL_TEST_PASS",
        "baseline_requests=21388800",
        "baseline_bytes=342220800",
        f"candidate_bytes={packed['bus_bytes_per_frame']}",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
