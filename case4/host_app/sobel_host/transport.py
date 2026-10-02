"""Serial I/O and an explicitly simulated device for protocol V1.

No transport claims that a byte written is an accepted or applied command.
Only parsed device replies carry those meanings.
"""

from collections.abc import Callable
import re
import time
from typing import Protocol

from .protocol import (
    ErrorCode, Frame, FrameParser, MAX_THRESHOLD, MessageType,
    PROTOCOL_VERSION, encode_frame,
)


class TransportError(RuntimeError):
    """An I/O failure requiring the caller to report/disconnect the session."""


class Transport(Protocol):
    @property
    def is_open(self) -> bool: ...
    def open(self) -> None: ...
    def close(self) -> None: ...
    def write(self, data: bytes) -> int: ...
    def read(self, max_bytes: int = 4096) -> bytes: ...


class SerialTransport:
    """A Windows COM port with nonblocking reads and bounded writes.

    The controller should run this transport on an I/O worker: Windows open
    and close calls can depend on driver behavior. URLs are deliberately not
    accepted, so a real-device selection cannot silently use a loopback URL.
    """

    def __init__(self, port: str, baudrate: int = 115200) -> None:
        if not re.fullmatch(r"(?:\\\\\.\\)?COM[1-9][0-9]*", port, flags=re.IGNORECASE):
            raise ValueError("请选择 Windows COM 串口，例如 COM3；不支持串口 URL。")
        if not isinstance(baudrate, int) or isinstance(baudrate, bool) or baudrate <= 0:
            raise ValueError("波特率必须是正整数。")
        self.port = port
        self.baudrate = baudrate
        self._serial = None

    @property
    def is_open(self) -> bool:
        return self._serial is not None and self._serial.is_open

    def open(self) -> None:
        if self.is_open:
            return
        try:
            import serial
            self._serial = serial.Serial(
                port=self.port, baudrate=self.baudrate,
                bytesize=serial.EIGHTBITS, parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE, timeout=0, write_timeout=0.2,
                xonxoff=False, rtscts=False, dsrdtr=False,
            )
        except Exception as exc:
            self._serial = None
            raise TransportError(f"无法打开 {self.port}：{exc}") from exc

    def close(self) -> None:
        connection, self._serial = self._serial, None
        if connection is not None:
            try:
                connection.close()
            except Exception as exc:
                raise TransportError(f"关闭 {self.port} 失败：{exc}") from exc

    def _require_open(self) -> None:
        if not self.is_open:
            raise TransportError("串口尚未连接。")

    def _failed(self, action: str, exc: Exception) -> TransportError:
        try:
            self.close()
        except TransportError:
            pass
        return TransportError(f"{self.port} {action}失败，连接已关闭：{exc}")

    def write(self, data: bytes) -> int:
        self._require_open()
        try:
            count = self._serial.write(data)
            if count != len(data):
                raise OSError(f"仅写出 {count}/{len(data)} 字节，命令状态未知")
            return count
        except Exception as exc:
            raise self._failed("写入", exc) from exc

    def read(self, max_bytes: int = 4096) -> bytes:
        self._require_open()
        if max_bytes < 1:
            raise ValueError("max_bytes must be positive")
        try:
            # timeout=0 makes this immediate, even when no bytes are available.
            return self._serial.read(max_bytes)
        except Exception as exc:
            raise self._failed("读取", exc) from exc


class SimulatedTransport:
    """A software-only model; it does not verify any FPGA or serial hardware.

    Each fresh open resets active threshold to 320. A valid SET immediately
    generates ACCEPTED, then applies after 150 ms at a simulated frame boundary.
    In no_apply mode it remains pending indefinitely; in reject_set mode SET
    returns INTERNAL_FAILURE; in no_response mode all input is ignored.
    ``clock`` allows tests to advance simulation time without sleeping.
    """

    SCENARIOS = ("normal", "no_response", "reject_set", "no_apply")

    def __init__(self, scenario: str = "normal", *, clock: Callable[[], float] = time.monotonic) -> None:
        if scenario not in self.SCENARIOS:
            raise ValueError(f"Unknown simulation scenario: {scenario}")
        self.scenario = scenario
        self._clock = clock
        self._is_open = False
        self._parser = FrameParser()
        self._outgoing = bytearray()
        self._pending: tuple[Frame, float] | None = None
        self.active_threshold = 320

    @property
    def is_open(self) -> bool:
        return self._is_open

    def open(self) -> None:
        if self._is_open:
            return
        self._parser = FrameParser()
        self._outgoing.clear()
        self._pending = None
        self.active_threshold = 320
        self._is_open = True

    def close(self) -> None:
        self._is_open = False
        self._pending = None
        self._outgoing.clear()
        self._parser = FrameParser()

    def _require_open(self) -> None:
        if not self._is_open:
            raise TransportError("模拟设备尚未连接。")

    def _respond(self, type_: MessageType, seq: int, value: int) -> None:
        self._outgoing.extend(encode_frame(Frame(type_, seq, value)))

    def _advance(self) -> None:
        if self._pending is not None and self.scenario != "no_apply":
            frame, due = self._pending
            if self._clock() >= due:
                self.active_threshold = frame.value
                self._pending = None
                self._respond(MessageType.APPLIED, frame.seq, self.active_threshold)

    def write(self, data: bytes) -> int:
        self._require_open()
        self._advance()
        if self.scenario == "no_response":
            return len(data)
        for frame in self._parser.feed(data):
            # Sequence zero is reserved and cannot correlate a response.
            if frame.seq == 0:
                continue
            if frame.version != PROTOCOL_VERSION:
                self._respond(MessageType.ERROR, frame.seq, ErrorCode.UNSUPPORTED_VERSION)
            elif frame.type == MessageType.PING:
                if frame.value != 0:
                    self._respond(MessageType.ERROR, frame.seq, ErrorCode.INVALID_VALUE)
                else:
                    self._respond(MessageType.PONG, frame.seq, 0)
            elif frame.type == MessageType.GET_THRESHOLD:
                if frame.value != 0:
                    self._respond(MessageType.ERROR, frame.seq, ErrorCode.INVALID_VALUE)
                else:
                    self._respond(MessageType.THRESHOLD, frame.seq, self.active_threshold)
            elif frame.type == MessageType.SET_THRESHOLD:
                if not 0 <= frame.value <= MAX_THRESHOLD:
                    self._respond(MessageType.ERROR, frame.seq, ErrorCode.INVALID_VALUE)
                elif self._pending is not None:
                    self._respond(MessageType.ERROR, frame.seq, ErrorCode.BUSY)
                elif self.scenario == "reject_set":
                    self._respond(MessageType.ERROR, frame.seq, ErrorCode.INTERNAL_FAILURE)
                else:
                    self._pending = (frame, self._clock() + 0.15)
                    self._respond(MessageType.ACCEPTED, frame.seq, frame.value)
            else:
                self._respond(MessageType.ERROR, frame.seq, ErrorCode.UNKNOWN_COMMAND)
        return len(data)

    def read(self, max_bytes: int = 4096) -> bytes:
        self._require_open()
        if max_bytes < 1:
            raise ValueError("max_bytes must be positive")
        self._advance()
        data = bytes(self._outgoing[:max_bytes])
        del self._outgoing[:max_bytes]
        return data
