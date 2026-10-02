"""New host/FPGA protocol V1 (not an existing board firmware protocol).

All multibyte fields are little endian. CRC-16/CCITT-FALSE covers the six
bytes VERSION through VALUE, excluding the two-byte sync header.
"""

from dataclasses import dataclass
from enum import IntEnum


HEADER = b"\xA5\x5A"
PROTOCOL_VERSION = 1
FRAME_SIZE = 10
MIN_THRESHOLD = 0
MAX_THRESHOLD = 2047


class MessageType(IntEnum):
    PING = 0x01
    SET_THRESHOLD = 0x02
    GET_THRESHOLD = 0x03
    PONG = 0x81
    ACCEPTED = 0x82
    APPLIED = 0x83
    THRESHOLD = 0x84
    ERROR = 0xFF


class ErrorCode(IntEnum):
    UNSUPPORTED_VERSION = 1
    UNKNOWN_COMMAND = 2
    INVALID_VALUE = 3
    BUSY = 4
    INTERNAL_FAILURE = 5


@dataclass(frozen=True)
class Frame:
    type: int
    seq: int
    value: int
    version: int = PROTOCOL_VERSION


def crc16_ccitt_false(data: bytes) -> int:
    """poly=0x1021, init=0xFFFF, refin/refout=False, xorout=0."""
    crc = 0xFFFF
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc


def encode_frame(frame: Frame) -> bytes:
    """Encode structural fields; command semantics are checked by the receiver."""
    for name, value, lower, upper in (
        ("version", frame.version, 0, 255),
        ("type", frame.type, 0, 255),
        ("seq", frame.seq, 1, 65535),
        ("value", frame.value, 0, 65535),
    ):
        if not isinstance(value, int) or isinstance(value, bool) or not lower <= value <= upper:
            raise ValueError(f"{name} must be an integer in {lower}..{upper}")
    body = bytes((frame.version, frame.type)) + frame.seq.to_bytes(2, "little") + frame.value.to_bytes(2, "little")
    return HEADER + body + crc16_ccitt_false(body).to_bytes(2, "little")


class FrameParser:
    """Incremental parser supporting arbitrary read boundaries and resync.

    A CRC-valid frame is delivered even if its version/type/value is unknown,
    allowing the endpoint to diagnose it. Sequence zero is likewise exposed
    but must never be executed by a device. Malformed CRC frames are discarded
    one byte at a time to avoid skipping a valid header inside corrupt input.
    """

    def __init__(self) -> None:
        self._buffer = bytearray()
        self.discarded_bytes = 0
        self.crc_errors = 0

    def feed(self, data: bytes) -> list[Frame]:
        self._buffer.extend(data)
        frames = []
        while self._buffer:
            offset = self._buffer.find(HEADER)
            if offset < 0:
                # Keep a final A5: it may be the first half of the next header.
                count = len(self._buffer) - int(self._buffer[-1] == HEADER[0])
                self.discarded_bytes += count
                del self._buffer[:count]
                break
            if offset:
                self.discarded_bytes += offset
                del self._buffer[:offset]
            if len(self._buffer) < FRAME_SIZE:
                break
            packet = self._buffer[:FRAME_SIZE]
            if crc16_ccitt_false(packet[2:8]) != int.from_bytes(packet[8:10], "little"):
                self.crc_errors += 1
                self.discarded_bytes += 1
                del self._buffer[0]
                continue
            frames.append(Frame(
                type=packet[3],
                seq=int.from_bytes(packet[4:6], "little"),
                value=int.from_bytes(packet[6:8], "little"),
                version=packet[2],
            ))
            del self._buffer[:FRAME_SIZE]
        return frames
