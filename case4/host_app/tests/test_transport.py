"""Simulated-device and mocked driver tests; no physical COM port is used."""

import binascii
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import MagicMock, patch

from sobel_host.protocol import ErrorCode, Frame, FrameParser, MessageType, encode_frame
from sobel_host.transport import SerialTransport, SimulatedTransport, TransportError


class SimulatorTests(unittest.TestCase):
    def setUp(self):
        self.now = 100.0
        self.device = SimulatedTransport(clock=lambda: self.now)
        self.device.open()

    def send(self, type_, seq=1, value=0, version=1):
        return self.device.write(encode_frame(Frame(type_, seq, value, version)))

    def receive(self):
        return FrameParser().feed(self.device.read())

    def test_ping_and_initial_get(self):
        self.send(MessageType.PING, 1)
        self.send(MessageType.GET_THRESHOLD, 2)
        self.assertEqual(self.receive(), [Frame(MessageType.PONG, 1, 0), Frame(MessageType.THRESHOLD, 2, 320)])

    def test_accepted_is_not_applied_and_get_reads_active(self):
        self.send(MessageType.SET_THRESHOLD, 2, 900)
        self.send(MessageType.GET_THRESHOLD, 3)
        self.assertEqual(self.receive(), [Frame(MessageType.ACCEPTED, 2, 900), Frame(MessageType.THRESHOLD, 3, 320)])
        self.assertEqual(self.device.active_threshold, 320)
        self.now += 0.2
        self.assertEqual(self.receive(), [Frame(MessageType.APPLIED, 2, 900)])
        self.send(MessageType.GET_THRESHOLD, 4)
        self.assertEqual(self.receive(), [Frame(MessageType.THRESHOLD, 4, 900)])

    def test_threshold_boundaries(self):
        for value in (0, 2047):
            self.send(MessageType.SET_THRESHOLD, value + 1, value)
            self.assertEqual(self.receive()[0].type, MessageType.ACCEPTED)
            self.now += 0.2
            self.assertEqual(self.receive(), [Frame(MessageType.APPLIED, value + 1, value)])

    def test_pending_set_returns_busy(self):
        self.send(MessageType.SET_THRESHOLD, 1, 400)
        self.send(MessageType.SET_THRESHOLD, 2, 500)
        self.assertEqual(self.receive(), [Frame(MessageType.ACCEPTED, 1, 400), Frame(MessageType.ERROR, 2, ErrorCode.BUSY)])
        self.now += 0.2
        self.assertEqual(self.receive(), [Frame(MessageType.APPLIED, 1, 400)])

    def test_invalid_commands_never_change_threshold(self):
        cases = [
            (Frame(MessageType.SET_THRESHOLD, 1, 2048), ErrorCode.INVALID_VALUE),
            (Frame(MessageType.SET_THRESHOLD, 2, 123, version=2), ErrorCode.UNSUPPORTED_VERSION),
            (Frame(0x40, 3, 123), ErrorCode.UNKNOWN_COMMAND),
            (Frame(MessageType.PING, 4, 1), ErrorCode.INVALID_VALUE),
            (Frame(MessageType.GET_THRESHOLD, 5, 1), ErrorCode.INVALID_VALUE),
        ]
        for frame, error in cases:
            self.device.write(encode_frame(frame))
            self.assertEqual(self.receive(), [Frame(MessageType.ERROR, frame.seq, error)])
        self.now += 1
        self.assertEqual(self.receive(), [])
        self.assertEqual(self.device.active_threshold, 320)

    def test_bad_crc_reserved_sequence_noise_never_mutate(self):
        corrupt = bytearray(encode_frame(Frame(MessageType.SET_THRESHOLD, 1, 500)))
        corrupt[9] ^= 1
        zero_seq_body = bytes.fromhex("01 02 00 00 F4 01")
        zero_seq = b"\xA5\x5A" + zero_seq_body + binascii.crc_hqx(zero_seq_body, 0xFFFF).to_bytes(2, "little")
        self.device.write(b"noise" + corrupt + zero_seq)
        self.now += 10
        self.assertEqual(self.receive(), [])
        self.assertEqual(self.device.active_threshold, 320)

    def test_fragmented_input_and_output(self):
        frame = Frame(MessageType.PING, 1, 0)
        packet = encode_frame(frame)
        self.device.write(packet[:4])
        self.assertEqual(self.device.read(), b"")
        self.device.write(packet[4:])
        parser = FrameParser()
        self.assertEqual(parser.feed(self.device.read(1)), [])
        self.assertEqual(parser.feed(self.device.read()), [Frame(MessageType.PONG, 1, 0)])

    def test_reopen_resets_pending_and_queued_replies(self):
        self.send(MessageType.SET_THRESHOLD, 1, 900)
        self.device.close()
        self.now += 1
        self.device.open()
        self.assertEqual(self.receive(), [])
        self.send(MessageType.GET_THRESHOLD, 2)
        self.assertEqual(self.receive(), [Frame(MessageType.THRESHOLD, 2, 320)])

    def test_failure_scenarios(self):
        for scenario in ("no_response", "reject_set", "no_apply"):
            with self.subTest(scenario=scenario):
                self.device = SimulatedTransport(scenario, clock=lambda: self.now)
                self.device.open()
                self.send(MessageType.SET_THRESHOLD, 1, 123)
                initial = self.receive()
                expected = {
                    "no_response": [],
                    "reject_set": [Frame(MessageType.ERROR, 1, ErrorCode.INTERNAL_FAILURE)],
                    "no_apply": [Frame(MessageType.ACCEPTED, 1, 123)],
                }[scenario]
                self.assertEqual(initial, expected)
                self.now += 10
                self.assertEqual(self.receive(), [])
                self.assertEqual(self.device.active_threshold, 320)

    def test_closed_transport_raises(self):
        self.device.close()
        with self.assertRaises(TransportError):
            self.device.read()
        with self.assertRaises(TransportError):
            self.device.write(b"abc")


class MockedSerialTests(unittest.TestCase):
    def setUp(self):
        self.connection = MagicMock()
        self.connection.is_open = True
        self.driver = SimpleNamespace(
            Serial=MagicMock(return_value=self.connection),
            EIGHTBITS=8, PARITY_NONE="N", STOPBITS_ONE=1,
        )
        self.patch = patch.dict(sys.modules, {"serial": self.driver})
        self.patch.start()
        self.addCleanup(self.patch.stop)

    def test_open_configuration_and_nonblocking_read(self):
        transport = SerialTransport("COM7", 57600)
        self.assertFalse(transport.is_open)
        transport.open()
        self.driver.Serial.assert_called_once_with(
            port="COM7", baudrate=57600, bytesize=8, parity="N", stopbits=1,
            timeout=0, write_timeout=0.2, xonxoff=False, rtscts=False, dsrdtr=False,
        )
        self.connection.read.return_value = b"a"
        self.assertEqual(transport.read(42), b"a")
        self.connection.read.assert_called_once_with(42)
        transport.close()
        self.assertFalse(transport.is_open)

    def test_com_names_only(self):
        for name in ("COM1", "com999", r"\\.\COM12"):
            SerialTransport(name)
        for name in ("loop://", "socket://localhost:123", "COM0", "COM1\\file", "/dev/ttyUSB0", ""):
            with self.subTest(name=name), self.assertRaises(ValueError):
                SerialTransport(name)

    def test_partial_write_closes_and_reports_unknown_result(self):
        transport = SerialTransport("COM1")
        transport.open()
        self.connection.write.return_value = 2
        with self.assertRaisesRegex(TransportError, "2/3"):
            transport.write(b"abc")
        self.assertFalse(transport.is_open)
        self.connection.close.assert_called_once()

    def test_unplug_read_failure_closes(self):
        transport = SerialTransport("COM1")
        transport.open()
        self.connection.read.side_effect = OSError("device removed")
        with self.assertRaisesRegex(TransportError, "device removed"):
            transport.read()
        self.assertFalse(transport.is_open)

    def test_open_failure_is_reported(self):
        self.driver.Serial.side_effect = OSError("access denied")
        transport = SerialTransport("COM1")
        with self.assertRaisesRegex(TransportError, "access denied"):
            transport.open()
        self.assertFalse(transport.is_open)


if __name__ == "__main__":
    unittest.main()
