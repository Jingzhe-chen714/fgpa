"""Wire-format checks independent of the GUI and any FPGA hardware."""

import binascii
import unittest

from sobel_host.protocol import Frame, FrameParser, MessageType, crc16_ccitt_false, encode_frame


class ProtocolTests(unittest.TestCase):
    def test_standard_crc_check_value(self):
        self.assertEqual(crc16_ccitt_false(b"123456789"), 0x29B1)
        self.assertEqual(crc16_ccitt_false(b""), 0xFFFF)

    def test_wire_byte_order_and_independent_crc(self):
        packet = encode_frame(Frame(MessageType.SET_THRESHOLD, 0x1234, 0x567))
        self.assertEqual(packet[:8], bytes.fromhex("A5 5A 01 02 34 12 67 05"))
        self.assertEqual(packet[8:], binascii.crc_hqx(packet[2:8], 0xFFFF).to_bytes(2, "little"))

    def test_all_possible_split_boundaries(self):
        expected = Frame(MessageType.THRESHOLD, 65535, 2047)
        packet = encode_frame(expected)
        for boundary in range(1, len(packet)):
            with self.subTest(boundary=boundary):
                parser = FrameParser()
                self.assertEqual(parser.feed(packet[:boundary]), [])
                self.assertEqual(parser.feed(packet[boundary:]), [expected])

    def test_coalesced_frames_and_bytewise_reads(self):
        frames = [Frame(MessageType.PONG, 1, 0), Frame(MessageType.APPLIED, 2, 0)]
        stream = b"".join(map(encode_frame, frames))
        self.assertEqual(FrameParser().feed(stream), frames)
        parser = FrameParser()
        actual = []
        for byte in stream:
            actual.extend(parser.feed(bytes([byte])))
        self.assertEqual(actual, frames)

    def test_corruption_resync_and_partial_header(self):
        expected = Frame(MessageType.PONG, 9, 0)
        corrupt = bytearray(encode_frame(Frame(MessageType.SET_THRESHOLD, 8, 123)))
        corrupt[6] ^= 1
        parser = FrameParser()
        self.assertEqual(parser.feed(b"noise\xA5"), [])
        actual = parser.feed(bytes(corrupt) + encode_frame(expected))
        self.assertEqual(actual, [expected])
        self.assertEqual(parser.crc_errors, 1)
        self.assertEqual(parser.discarded_bytes, 16)

    def test_nested_header_in_damaged_frame_does_not_hide_good_frame(self):
        expected = Frame(MessageType.THRESHOLD, 100, 55)
        parser = FrameParser()
        self.assertEqual(parser.feed(b"\xA5\x5A\x00" + encode_frame(expected)), [expected])
        self.assertEqual(parser.crc_errors, 1)
        self.assertEqual(parser.discarded_bytes, 3)

    def test_unknown_version_type_preserved(self):
        frame = Frame(0x71, 7, 4000, version=2)
        self.assertEqual(FrameParser().feed(encode_frame(frame)), [frame])

    def test_noise_does_not_grow_buffer(self):
        parser = FrameParser()
        self.assertEqual(parser.feed(b"\x00" * 100000 + b"\xA5"), [])
        self.assertEqual(parser.discarded_bytes, 100000)
        frame = Frame(MessageType.PONG, 3, 0)
        self.assertEqual(parser.feed(encode_frame(frame)[1:]), [frame])

    def test_encode_rejects_out_of_range_structural_fields(self):
        for frame in (Frame(1, 0, 0), Frame(1, 65536, 0), Frame(1, 1, -1),
                      Frame(256, 1, 0), Frame(1, 1, 0, 256), Frame(1, True, 0)):
            with self.subTest(frame=frame), self.assertRaises(ValueError):
                encode_frame(frame)


if __name__ == "__main__":
    unittest.main()
