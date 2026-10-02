"""Software-only transaction tests using independent, scripted byte replies.

These tests do not require a COM port and do not validate any FPGA hardware.
"""
from __future__ import annotations

from collections import deque
import threading
import time
import unittest

from sobel_host.controller import DeviceController
from sobel_host.protocol import ErrorCode, Frame, FrameParser, MessageType, encode_frame
from sobel_host.transport import SimulatedTransport


class ScriptedTransport:
    """Thread-safe fake I/O; replies are chosen by the test, not the controller."""

    def __init__(self):
        self.is_open = False
        self.writes = []
        self._reads = deque()
        self._lock = threading.Lock()
        self.fail_write = False
        self.short_write = False
        self.fail_read = False
        self.fail_open = False
        self.write_gate = None
        self.write_entered = threading.Event()

    def open(self):
        if self.fail_open:
            raise OSError("scripted port-open failure")
        self.is_open = True

    def close(self):
        self.is_open = False

    def write(self, data):
        self.write_entered.set()
        if self.write_gate is not None:
            self.write_gate.wait(1)
        if self.fail_write:
            raise OSError("scripted partial-transmission failure")
        with self._lock:
            self.writes.append(bytes(data))
        return len(data) - 1 if self.short_write else len(data)

    def read(self, max_bytes=4096):
        if self.fail_read:
            raise OSError("scripted cable removal")
        with self._lock:
            if not self._reads:
                return b""
            data = self._reads.popleft()
            if len(data) > max_bytes:
                self._reads.appendleft(data[max_bytes:])
            return data[:max_bytes]

    def inject(self, data):
        with self._lock:
            self._reads.append(bytes(data))

    def requests(self):
        with self._lock:
            return FrameParser().feed(b"".join(self.writes))


class ControllerTests(unittest.TestCase):
    def setUp(self):
        self.controller = DeviceController(response_timeout=0.25, apply_timeout=0.25)
        self.transport = ScriptedTransport()
        self.events = []

    def tearDown(self):
        self.controller.disconnect()
        worker = self.controller._worker
        if worker:
            if self.transport.write_gate is not None:
                self.transport.write_gate.set()
            worker.join(timeout=1)
            self.assertFalse(worker.is_alive(), "I/O worker did not stop")

    def tick(self):
        self.events.extend(self.controller.poll())

    def wait_for(self, predicate, timeout=1.0):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            self.tick()
            if predicate():
                return
            time.sleep(0.002)
        self.fail(f"condition timed out: stage={self.controller.stage}, status={self.controller.status}")

    def wait_sent(self, kind):
        self.wait_for(lambda: self.controller.pending is not None
                      and self.controller.pending.frame.type == kind
                      and self.controller.pending.sent)
        return self.controller.pending.frame

    def reply(self, type_, value, *, seq=None, version=1):
        if seq is None:
            self.assertIsNotNone(self.controller.pending)
            seq = self.controller.pending.frame.seq
        self.transport.inject(encode_frame(Frame(type_, seq, value, version)))

    def connect_ready(self, threshold=320):
        self.controller.connect(self.transport, label="test-only transport", simulated=True)
        self.wait_sent(MessageType.PING)
        self.assertFalse(self.controller.verified)
        self.reply(MessageType.PONG, 0)
        self.wait_sent(MessageType.GET_THRESHOLD)
        self.reply(MessageType.THRESHOLD, threshold)
        self.wait_for(lambda: self.controller.pending is None)
        self.assertTrue(self.controller.verified)
        self.assertEqual(self.controller.active_threshold, threshold)

    def begin_set(self, value=640):
        self.controller.set_threshold(value)
        return self.wait_sent(MessageType.SET_THRESHOLD)

    def test_connect_checks_protocol_then_reads_current_threshold(self):
        self.connect_ready()
        self.assertEqual([f.type for f in self.transport.requests()],
                         [MessageType.PING, MessageType.GET_THRESHOLD])
        self.assertEqual(self.controller.stage, "readback")
        self.assertFalse(self.controller.command_applied)
        self.assertTrue(any(event.kind == "TX" and event.data for event in self.events))
        self.assertTrue(any(event.kind == "RX" and event.data for event in self.events))

    def test_sent_accepted_and_applied_are_distinct(self):
        self.connect_ready()
        self.begin_set(640)
        self.assertTrue(self.controller.command_sent)
        self.assertFalse(self.controller.command_accepted)
        self.assertFalse(self.controller.command_applied)
        self.assertEqual(self.controller.active_threshold, 320)
        self.assertTrue(self.controller.uncertain)
        self.reply(MessageType.ACCEPTED, 640)
        self.wait_for(lambda: self.controller.stage == "accepted")
        self.assertTrue(self.controller.command_accepted)
        self.assertFalse(self.controller.command_applied)
        self.assertEqual(self.controller.active_threshold, 320)
        self.reply(MessageType.APPLIED, 640)
        self.wait_for(lambda: self.controller.stage == "applied")
        self.assertEqual(self.controller.active_threshold, 640)
        self.assertTrue(self.controller.command_applied)
        self.assertFalse(self.controller.uncertain)

    def test_applied_is_valid_when_accepted_packet_was_lost(self):
        self.connect_ready()
        self.begin_set(1000)
        self.reply(MessageType.APPLIED, 1000)
        self.wait_for(lambda: self.controller.pending is None)
        self.assertTrue(self.controller.command_accepted)
        self.assertTrue(self.controller.command_applied)
        self.assertEqual(self.controller.active_threshold, 1000)

    def test_wrong_sequence_and_stale_reply_cannot_complete_set(self):
        self.connect_ready()
        request = self.begin_set()
        self.reply(MessageType.APPLIED, 640, seq=request.seq - 1)
        self.wait_for(lambda: any("非当前响应" in event.text for event in self.events))
        self.assertIsNotNone(self.controller.pending)
        self.assertEqual(self.controller.active_threshold, 320)
        self.assertFalse(self.controller.command_applied)
        self.reply(MessageType.APPLIED, 640)
        self.wait_for(lambda: self.controller.pending is None)
        self.reply(MessageType.APPLIED, 7, seq=request.seq)
        self.wait_for(lambda: sum("非当前响应" in event.text for event in self.events) >= 2)
        self.assertEqual(self.controller.active_threshold, 640)

    def test_wrong_response_type_is_ignored(self):
        self.connect_ready()
        self.begin_set()
        self.reply(MessageType.THRESHOLD, 640)
        self.wait_for(lambda: any("不匹配的响应" in event.text for event in self.events))
        self.assertEqual(self.controller.active_threshold, 320)
        self.assertIsNotNone(self.controller.pending)

    def test_wrong_set_value_fails_without_claiming_success(self):
        self.connect_ready()
        self.begin_set()
        self.reply(MessageType.APPLIED, 641)
        self.wait_for(lambda: self.controller.stage == "error")
        self.assertIsNone(self.controller.active_threshold)
        self.assertTrue(self.controller.uncertain)
        self.assertFalse(self.controller.command_applied)

    def test_out_of_range_readback_does_not_update_known_value(self):
        self.connect_ready()
        self.controller.get_threshold()
        self.wait_sent(MessageType.GET_THRESHOLD)
        self.reply(MessageType.THRESHOLD, 2048)
        self.wait_for(lambda: self.controller.stage == "error")
        self.assertEqual(self.controller.active_threshold, 320)

    def test_protocol_version_mismatch_revokes_verification(self):
        self.connect_ready()
        self.begin_set()
        self.reply(MessageType.APPLIED, 640, version=2)
        self.wait_for(lambda: self.controller.stage == "error")
        self.assertFalse(self.controller.verified)
        self.assertIsNone(self.controller.active_threshold)
        with self.assertRaises(RuntimeError):
            self.controller.set_threshold(10)

    def test_ping_timeout_never_verifies_the_device(self):
        self.controller.connect(self.transport)
        self.wait_for(lambda: self.controller.stage == "timeout")
        self.assertFalse(self.controller.verified)
        self.assertIsNone(self.controller.active_threshold)
        self.assertEqual(len(self.transport.requests()), 1)

    def test_failed_manual_connection_recheck_revokes_old_verification(self):
        self.connect_ready()
        self.controller.ping()
        self.assertFalse(self.controller.verified)
        self.wait_sent(MessageType.PING)
        self.wait_for(lambda: self.controller.stage == "timeout")
        self.assertFalse(self.controller.verified)
        with self.assertRaises(RuntimeError):
            self.controller.set_threshold(640)

    def test_read_timeout_is_not_a_successful_readback(self):
        self.connect_ready()
        previous_confirmation = self.controller.last_confirmed_at
        self.controller.get_threshold()
        self.wait_sent(MessageType.GET_THRESHOLD)
        self.wait_for(lambda: self.controller.stage == "timeout")
        self.assertEqual(self.controller.last_confirmed_at, previous_confirmation)
        self.assertIsNone(self.controller.pending)

    def test_set_response_timeout_does_not_retry_and_readback_recovers(self):
        self.connect_ready()
        self.begin_set()
        self.wait_for(lambda: self.controller.stage == "timeout")
        self.assertTrue(self.controller.uncertain)
        self.assertIsNone(self.controller.active_threshold)
        self.assertEqual(sum(f.type == MessageType.SET_THRESHOLD for f in self.transport.requests()), 1)
        self.controller.get_threshold()
        self.wait_sent(MessageType.GET_THRESHOLD)
        self.reply(MessageType.THRESHOLD, 640)
        self.wait_for(lambda: self.controller.pending is None)
        self.assertFalse(self.controller.uncertain)
        self.assertEqual(self.controller.active_threshold, 640)
        self.assertFalse(self.controller.command_applied)

    def test_accepted_timeout_is_uncertain_and_does_not_retry(self):
        self.connect_ready()
        self.begin_set()
        self.reply(MessageType.ACCEPTED, 640)
        self.wait_for(lambda: self.controller.stage == "accepted")
        self.wait_for(lambda: self.controller.stage == "timeout")
        self.assertTrue(self.controller.command_accepted)
        self.assertFalse(self.controller.command_applied)
        self.assertTrue(self.controller.uncertain)
        self.assertIsNone(self.controller.active_threshold)
        self.assertEqual(sum(f.type == MessageType.SET_THRESHOLD for f in self.transport.requests()), 1)

    def test_duplicate_accepted_does_not_extend_apply_deadline(self):
        self.connect_ready()
        self.begin_set()
        self.reply(MessageType.ACCEPTED, 640)
        self.wait_for(lambda: self.controller.stage == "accepted")
        deadline = self.controller.pending.deadline
        before_count = sum(event.kind == "RX" for event in self.events)
        self.reply(MessageType.ACCEPTED, 640)
        self.wait_for(lambda: sum(event.kind == "RX" for event in self.events) > before_count)
        self.assertEqual(self.controller.pending.deadline, deadline)

    def test_rejection_before_acceptance_preserves_known_threshold(self):
        self.connect_ready()
        self.begin_set()
        self.reply(MessageType.ERROR, ErrorCode.BUSY)
        self.wait_for(lambda: self.controller.stage == "error")
        self.assertEqual(self.controller.active_threshold, 320)
        self.assertFalse(self.controller.command_accepted)
        self.assertFalse(self.controller.command_applied)
        self.assertFalse(self.controller.uncertain)

    def test_error_after_acceptance_invalidates_known_threshold(self):
        self.connect_ready()
        self.begin_set()
        self.reply(MessageType.ACCEPTED, 640)
        self.wait_for(lambda: self.controller.stage == "accepted")
        self.reply(MessageType.ERROR, ErrorCode.INTERNAL_FAILURE)
        self.wait_for(lambda: self.controller.stage == "error")
        self.assertIsNone(self.controller.active_threshold)
        self.assertTrue(self.controller.uncertain)
        self.assertFalse(self.controller.command_applied)

    def test_internal_failure_is_uncertain_even_if_accepted_reply_was_lost(self):
        self.connect_ready()
        self.begin_set()
        # Hardware may have accepted the SET but its ACCEPTED packet was lost.
        # INTERNAL_FAILURE cannot prove that the old active value survived.
        self.reply(MessageType.ERROR, ErrorCode.INTERNAL_FAILURE)
        self.wait_for(lambda: self.controller.stage == "error")
        self.assertIsNone(self.controller.active_threshold)
        self.assertIsNone(self.controller.last_confirmed_at)
        self.assertTrue(self.controller.uncertain)
        self.assertFalse(self.controller.command_applied)

    def test_disconnect_midcommand_discards_stale_worker_responses(self):
        self.connect_ready()
        request = self.begin_set()
        self.reply(MessageType.APPLIED, 640)
        self.controller.disconnect()
        self.controller._worker.join(timeout=1)
        self.tick()
        self.assertEqual(self.controller.connection, "disconnected")
        self.assertIsNone(self.controller.active_threshold)
        self.assertIsNone(self.controller.pending)
        self.assertTrue(self.controller.uncertain)
        self.assertFalse(self.controller.command_applied)

        self.transport = ScriptedTransport()
        self.connect_ready(threshold=500)
        self.assertGreater(self.transport.requests()[0].seq, request.seq)
        self.assertFalse(self.controller.uncertain)
        self.assertEqual(self.controller.active_threshold, 500)

    def test_reconnect_resets_partial_frame_parser(self):
        self.connect_ready()
        request = self.begin_set()
        self.transport.inject(encode_frame(Frame(MessageType.APPLIED, request.seq, 640))[:7])
        self.wait_for(lambda: any(event.kind == "RX" and len(event.data) == 7 for event in self.events))
        self.controller.disconnect()
        self.controller._worker.join(timeout=1)
        self.transport = ScriptedTransport()
        self.connect_ready(threshold=999)
        self.assertEqual(self.controller.active_threshold, 999)

    def test_write_failure_disconnects_without_claiming_acceptance(self):
        self.connect_ready()
        self.transport.fail_write = True
        self.controller.set_threshold(640)
        self.wait_for(lambda: self.controller.connection == "disconnected")
        self.assertEqual(self.controller.stage, "error")
        self.assertIsNone(self.controller.active_threshold)
        self.assertTrue(self.controller.uncertain)
        self.assertFalse(self.controller.command_accepted)
        self.assertFalse(self.controller.command_applied)

    def test_partial_write_disconnects_and_marks_result_unknown(self):
        self.connect_ready()
        self.transport.short_write = True
        self.controller.set_threshold(640)
        self.wait_for(lambda: self.controller.connection == "disconnected")
        self.assertTrue(self.controller.uncertain)
        self.assertIsNone(self.controller.active_threshold)
        self.assertFalse(self.controller.command_sent)

    def test_cable_removal_resets_connection_and_known_value(self):
        self.connect_ready()
        self.transport.fail_read = True
        self.wait_for(lambda: self.controller.connection == "disconnected")
        self.assertFalse(self.controller.verified)
        self.assertIsNone(self.controller.active_threshold)

    def test_port_open_failure_leaves_usable_disconnected_state(self):
        self.transport.fail_open = True
        self.controller.connect(self.transport)
        self.wait_for(lambda: self.controller.connection == "disconnected")
        self.assertEqual(self.controller.stage, "error")
        self.assertFalse(self.controller.verified)
        self.assertFalse(self.controller.command_sent)

    def test_fragmented_and_combined_reply_frames(self):
        self.connect_ready()
        request = self.begin_set(2047)
        accepted = encode_frame(Frame(MessageType.ACCEPTED, request.seq, 2047))
        applied = encode_frame(Frame(MessageType.APPLIED, request.seq, 2047))
        self.transport.inject(accepted[:1])
        self.transport.inject(accepted[1:7])
        self.transport.inject(accepted[7:] + applied)
        self.wait_for(lambda: self.controller.stage == "applied")
        self.assertEqual(self.controller.active_threshold, 2047)
        self.assertTrue(self.controller.command_accepted)
        self.assertTrue(self.controller.command_applied)

    def test_corrupt_reply_is_ignored_until_valid_reply_arrives(self):
        self.connect_ready()
        request = self.begin_set()
        packet = bytearray(encode_frame(Frame(MessageType.APPLIED, request.seq, 640)))
        packet[-1] ^= 1
        self.transport.inject(b"noise" + packet)
        self.wait_for(lambda: any("校验错误" in event.text for event in self.events))
        self.assertIsNotNone(self.controller.pending)
        self.assertFalse(self.controller.command_applied)
        self.reply(MessageType.APPLIED, 640)
        self.wait_for(lambda: self.controller.stage == "applied")

    def test_invalid_input_is_rejected_without_sending_or_mutation(self):
        self.connect_ready()
        for value in (-1, 2048, True, 12.5, "320", None):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    self.controller.set_threshold(value)
        self.assertEqual(len(self.transport.requests()), 2)
        self.assertEqual(self.controller.active_threshold, 320)
        self.assertIsNone(self.controller.pending)

    def test_set_requires_connection_verification_and_idle_transaction(self):
        with self.assertRaises(RuntimeError):
            self.controller.set_threshold(10)
        self.controller.connect(self.transport)
        self.wait_sent(MessageType.PING)
        with self.assertRaises(RuntimeError):
            self.controller.set_threshold(10)
        self.reply(MessageType.PONG, 0)
        self.wait_sent(MessageType.GET_THRESHOLD)
        self.reply(MessageType.THRESHOLD, 320)
        self.wait_for(lambda: self.controller.pending is None)
        self.begin_set(10)
        with self.assertRaises(RuntimeError):
            self.controller.set_threshold(20)
        self.assertEqual(self.controller.pending.frame.value, 10)

    def test_sequence_exhaustion_never_wraps_or_reuses_zero(self):
        self.connect_ready()
        self.controller._sequence = 65534
        request = self.begin_set()
        self.assertEqual(request.seq, 65535)
        self.reply(MessageType.APPLIED, 640)
        self.wait_for(lambda: self.controller.pending is None)
        with self.assertRaises(RuntimeError):
            self.controller.set_threshold(641)
        self.assertEqual(self.controller._sequence, 65535)
        self.assertEqual(self.controller.active_threshold, 640)
        self.assertIsNone(self.controller.pending)

    def test_exhausted_sequence_during_auto_ping_does_not_crash_poll(self):
        self.controller._sequence = 65535
        self.controller.connect(self.transport)
        self.wait_for(lambda: self.controller.stage == "error")
        self.assertFalse(self.controller.verified)
        self.assertIsNone(self.controller.pending)
        self.assertEqual(self.transport.requests(), [])
        self.assertIn("序号", self.controller.status)

    def test_exhausted_sequence_during_auto_get_does_not_crash_poll(self):
        self.controller._sequence = 65534
        self.controller.connect(self.transport)
        request = self.wait_sent(MessageType.PING)
        self.assertEqual(request.seq, 65535)
        self.reply(MessageType.PONG, 0)
        self.wait_for(lambda: self.controller.stage == "error")
        self.assertIsNone(self.controller.pending)
        self.assertIsNone(self.controller.active_threshold)
        self.assertEqual(len(self.transport.requests()), 1)
        self.assertIn("序号", self.controller.status)

    def test_slow_write_runs_off_the_polling_thread(self):
        self.connect_ready()
        self.transport.write_entered.clear()
        self.transport.write_gate = threading.Event()
        start = time.monotonic()
        self.controller.set_threshold(640)
        self.assertLess(time.monotonic() - start, 0.1)
        self.assertTrue(self.transport.write_entered.wait(0.5))
        start = time.monotonic()
        self.tick()
        self.assertLess(time.monotonic() - start, 0.1)
        self.assertFalse(self.controller.command_sent)
        self.transport.write_gate.set()
        self.wait_sent(MessageType.SET_THRESHOLD)


class SimulatedEndToEndTests(unittest.TestCase):
    def test_real_controller_and_simulated_device_round_trip(self):
        controller = DeviceController()
        controller.connect(SimulatedTransport(), label="software-only simulation", simulated=True)
        try:
            deadline = time.monotonic() + 2
            while controller.active_threshold is None and time.monotonic() < deadline:
                controller.poll()
                time.sleep(0.005)
            self.assertEqual(controller.active_threshold, 320)
            controller.set_threshold(0)
            observed_accepted = False
            while not controller.command_applied and time.monotonic() < deadline:
                controller.poll()
                if controller.command_accepted and not controller.command_applied:
                    observed_accepted = True
                    self.assertEqual(controller.active_threshold, 320)
                time.sleep(0.005)
            self.assertTrue(observed_accepted)
            self.assertTrue(controller.command_applied)
            self.assertEqual(controller.active_threshold, 0)
        finally:
            controller.disconnect()
            controller._worker.join(timeout=1)


if __name__ == "__main__":
    unittest.main()
