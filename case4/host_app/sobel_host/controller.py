"""Transaction state machine; all blocking device I/O stays on one worker thread."""
from __future__ import annotations

from dataclasses import dataclass
import queue
import threading
import time

from .protocol import Frame, FrameParser, MessageType, encode_frame


@dataclass(frozen=True)
class Event:
    kind: str
    text: str
    data: bytes = b""


@dataclass
class Pending:
    frame: Frame
    deadline: float
    sent: bool = False
    accepted: bool = False


class _DeviceWorker(threading.Thread):
    def __init__(self, transport):
        super().__init__(name="sobel-serial-io", daemon=True)
        self.transport = transport
        self.stop_event = threading.Event()
        self.commands = queue.SimpleQueue()
        self.events = queue.SimpleQueue()

    def run(self):
        try:
            self.transport.open()
            if self.stop_event.is_set():
                return
            self.events.put(("opened", None))
            while not self.stop_event.is_set():
                try:
                    frame = self.commands.get_nowait()
                except queue.Empty:
                    frame = None
                if frame is not None:
                    payload = encode_frame(frame)
                    written = self.transport.write(payload)
                    if written != len(payload):
                        raise OSError(f"串口只写入 {written}/{len(payload)} 字节")
                    self.events.put(("sent", (frame, payload, time.monotonic())))
                chunk = self.transport.read(4096)
                if chunk:
                    self.events.put(("data", chunk))
                self.stop_event.wait(0.01)
        except Exception as exc:
            self.events.put(("fault", str(exc)))
        finally:
            try:
                self.transport.close()
            except Exception as exc:
                self.events.put(("close_error", str(exc)))
            self.events.put(("closed", None))


class DeviceController:
    def __init__(self, response_timeout=1.0, apply_timeout=2.0):
        self.response_timeout = response_timeout
        self.apply_timeout = apply_timeout
        self.connection = "disconnected"
        self.verified = False
        self.active_threshold = None
        self.pending: Pending | None = None
        self.stage = "idle"
        self.status = "请选择模拟设备或真实串口，然后连接。"
        self.uncertain = False
        self.simulated = False
        self.label = "未连接"
        self.operation = None
        self.command_sent = False
        self.command_accepted = False
        self.command_applied = False
        self.last_set_value = None
        self.last_confirmed_at = None
        self._sequence = 0
        self._worker = None
        self._parser = FrameParser()
        self._events = []

    def _log(self, kind, text, data=b""):
        self._events.append(Event(kind, text, data))

    def connect(self, transport, label="设备", simulated=False):
        if self.connection != "disconnected":
            raise RuntimeError("请先断开当前连接。")
        if self._worker and self._worker.is_alive():
            raise RuntimeError("串口正在关闭，请稍后再连接。")
        self.simulated = simulated
        self.label = label
        self.connection = "connecting"
        self.verified = False
        self.active_threshold = None
        self.last_confirmed_at = None
        self.pending = None
        self.stage = "idle"
        self.uncertain = False
        self.operation = None
        self.command_sent = self.command_accepted = self.command_applied = False
        self.last_set_value = None
        self._parser = FrameParser()
        self.status = "正在连接…"
        self._log("INFO", f"连接 {label}" + (" · 模拟设备，未连接 FPGA" if simulated else " · 真实串口"))
        self._worker = _DeviceWorker(transport)
        self._worker.start()

    def disconnect(self):
        if self._worker:
            self._worker.stop_event.set()
        was_pending = self.pending is not None
        self.connection = "disconnected"
        self.verified = False
        self.active_threshold = None
        self.last_confirmed_at = None
        self.pending = None
        self.stage = "idle"
        self.uncertain = was_pending
        self.command_sent = self.command_accepted = self.command_applied = False
        self.status = "已断开；设备当前阈值未知。" + (" 未完成命令的结果需要重新读回核实。" if was_pending else "")
        self._log("INFO", self.status)

    def _request(self, kind, value=0):
        if self.connection != "connected":
            raise RuntimeError("请先连接设备。")
        if self.pending is not None:
            raise RuntimeError("上一条命令仍在等待响应。")
        if kind != MessageType.PING and not self.verified:
            raise RuntimeError("请先通过连接检查，确认设备支持协议 V1。")
        # Never reuse a sequence in a live connection: delayed replies cannot alias.
        if self._sequence >= 65535:
            raise RuntimeError("本次应用的命令序号已用完，请重启上位机并重新连接。")
        self._sequence += 1
        frame = Frame(kind, self._sequence, value)
        self.pending = Pending(frame, time.monotonic() + self.response_timeout + 0.5)
        self.operation = kind
        self.stage = "queued"
        self.command_sent = self.command_accepted = self.command_applied = False
        if kind == MessageType.SET_THRESHOLD:
            self.last_set_value = value
            self.uncertain = True
        self.status = "命令已排队，等待串口发送。"
        self._worker.commands.put(frame)

    def ping(self):
        self._request(MessageType.PING)
        self.verified = False

    def _automatic_request(self, action):
        try:
            action()
        except RuntimeError as exc:
            self.stage = "error"
            self.status = str(exc)
            self._log("ERROR", self.status)

    def get_threshold(self):
        self._request(MessageType.GET_THRESHOLD)

    def set_threshold(self, value):
        if not isinstance(value, int) or isinstance(value, bool) or not 0 <= value <= 2047:
            raise ValueError("阈值必须是 0–2047 的整数。")
        self._request(MessageType.SET_THRESHOLD, value)

    def poll(self):
        if self._worker:
            for _ in range(256):
                try:
                    kind, payload = self._worker.events.get_nowait()
                except queue.Empty:
                    break
                if self.connection == "disconnected":
                    continue
                if kind == "opened":
                    self.connection = "connected"
                    self.status = "串口已打开，正在检查协议 V1。"
                    self._log("INFO", self.status)
                    self._automatic_request(self.ping)
                elif kind == "sent":
                    frame, raw, timestamp = payload
                    self._log("TX", f"{MessageType(frame.type).name}  seq={frame.seq}  value={frame.value}", raw)
                    if self.pending and self.pending.frame.seq == frame.seq:
                        self.pending.sent = True
                        self.pending.deadline = timestamp + self.response_timeout
                        self.command_sent = True
                        self.stage = "sent"
                        self.status = "命令已发送，等待设备响应。"
                elif kind == "data":
                    self._log("RX", "收到字节", payload)
                    old_crc = self._parser.crc_errors
                    old_discard = self._parser.discarded_bytes
                    for frame in self._parser.feed(payload):
                        self._handle_frame(frame)
                    if self._parser.crc_errors != old_crc or self._parser.discarded_bytes != old_discard:
                        self._log("WARN", "丢弃噪声或校验错误数据，继续寻找完整帧。")
                elif kind == "fault":
                    self.disconnect()
                    self.stage = "error"
                    self.status = "连接或通信失败：" + payload
                    self._log("ERROR", self.status)
                elif kind == "closed":
                    self.disconnect()
                elif kind == "close_error":
                    self._log("WARN", "关闭串口时出错：" + payload)
        if self.pending and time.monotonic() >= self.pending.deadline:
            is_set = self.pending.frame.type == MessageType.SET_THRESHOLD
            accepted = self.pending.accepted
            self.pending = None
            self.stage = "timeout"
            if is_set:
                self.uncertain = True
                self.active_threshold = None
                self.last_confirmed_at = None
                self.status = ("设备已接受，但未收到生效确认。" if accepted else "未收到设置响应。") + " 当前值未知，请读取阈值核实；不会自动重发。"
            else:
                self.status = "设备响应超时。请检查连接、波特率及 FPGA 是否实现协议 V1。"
            self._log("ERROR", self.status)
        events, self._events = self._events, []
        return events

    def _protocol_failure(self, message):
        if self.pending and self.pending.frame.type == MessageType.SET_THRESHOLD:
            self.uncertain = True
            self.active_threshold = None
            self.last_confirmed_at = None
        self.pending = None
        self.stage = "error"
        self.status = message
        self._log("ERROR", message)

    def _handle_frame(self, frame):
        pending = self.pending
        if not pending or frame.seq != pending.frame.seq or not pending.sent:
            self._log("WARN", f"忽略过期或非当前响应 seq={frame.seq} type=0x{int(frame.type):02X}")
            return
        if frame.version != 1:
            self.verified = False
            self._protocol_failure(f"设备协议版本 {frame.version} 不受支持，需要 V1。")
            return
        if frame.type == MessageType.ERROR:
            errors = {1: "协议版本不支持", 2: "命令不支持", 3: "参数超出范围", 4: "设备忙", 5: "设备内部故障"}
            is_set = pending.frame.type == MessageType.SET_THRESHOLD
            ambiguous = is_set and (pending.accepted or frame.value not in (1, 2, 3, 4))
            if ambiguous:
                self.uncertain = True
                self.active_threshold = None
                self.last_confirmed_at = None
            elif is_set:
                self.uncertain = False
            if frame.value == 1:
                self.verified = False
            self.pending = None
            self.stage = "error"
            self.status = "设备拒绝或无法完成命令：" + errors.get(frame.value, f"未知错误 {frame.value}")
            if ambiguous:
                self.status += "。当前值未知，请读取阈值核实。"
            self._log("ERROR", self.status)
            return
        request_type = pending.frame.type
        if request_type == MessageType.PING and frame.type == MessageType.PONG and frame.value == 0:
            self.pending = None
            self.verified = True
            self.stage = "confirmed"
            self.status = "连接检查通过；正在读取当前阈值。"
            self._log("INFO", self.status)
            self._automatic_request(self.get_threshold)
        elif request_type == MessageType.GET_THRESHOLD and frame.type == MessageType.THRESHOLD:
            if not 0 <= frame.value <= 2047:
                self._protocol_failure("读回阈值超出 0–2047，未更新显示。")
                return
            self.active_threshold = frame.value
            self.last_confirmed_at = time.monotonic()
            self.pending = None
            self.uncertain = False
            self.stage = "readback"
            self.status = f"已读回设备当前阈值：{frame.value}。"
            self._log("INFO", self.status)
        elif request_type == MessageType.SET_THRESHOLD and frame.type in (MessageType.ACCEPTED, MessageType.APPLIED):
            if frame.value != pending.frame.value:
                self._protocol_failure("设备返回的阈值与请求不一致；当前值未知，请重新读回。")
                return
            if frame.type == MessageType.ACCEPTED:
                if not pending.accepted:
                    pending.accepted = True
                    pending.deadline = time.monotonic() + self.apply_timeout
                self.command_accepted = True
                self.stage = "accepted"
                self.status = f"设备已接受 {frame.value}，等待实际生效确认。"
                self._log("INFO", self.status)
            else:
                # APPLIED is stronger evidence even if ACCEPTED was lost in transit.
                self.command_accepted = self.command_applied = True
                self.active_threshold = frame.value
                self.last_confirmed_at = time.monotonic()
                self.pending = None
                self.uncertain = False
                self.stage = "applied"
                self.status = f"设备已确认阈值 {frame.value} 生效。"
                self._log("INFO", self.status)
        else:
            self._log("WARN", f"忽略不匹配的响应 type=0x{int(frame.type):02X} value={frame.value}，继续等待。")
