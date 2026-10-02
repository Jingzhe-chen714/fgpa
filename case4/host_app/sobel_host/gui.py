"""Chinese desktop UI. The model owns evidence; the UI never guesses device state."""
from __future__ import annotations

import csv
from collections import deque
from datetime import datetime
from pathlib import Path

from PySide6.QtCore import Qt, QTimer
from PySide6.QtGui import QFont
from PySide6.QtWidgets import (
    QApplication, QComboBox, QFileDialog, QFrame, QGridLayout, QGroupBox,
    QHBoxLayout, QHeaderView, QLabel, QMainWindow, QMessageBox, QPushButton,
    QSlider, QSpinBox, QTableWidget, QTableWidgetItem, QVBoxLayout, QWidget,
)

from .controller import DeviceController
from .protocol import MessageType
from .transport import SerialTransport, SimulatedTransport


STYLE = """
QMainWindow, QWidget#root { background: #F3F6FA; color: #172B4D; }
QWidget { font-family: 'Microsoft YaHei UI', 'Microsoft YaHei', 'Segoe UI'; font-size: 10pt; }
QLabel { color: #24364B; }
QLabel#title { font-size: 23pt; font-weight: 700; color: #10243A; }
QLabel#subtitle { color: #627389; font-size: 10pt; }
QLabel#badge { color: #245EA7; background: #E2ECF9; padding: 7px 14px; border-radius: 12px; font-weight: 600; }
QLabel#banner { padding: 12px 15px; border-radius: 8px; font-weight: 600; }
QGroupBox { background: white; border: 1px solid #DEE5EF; border-radius: 10px; margin-top: 13px; padding: 17px 15px 14px; font-weight: 600; }
QGroupBox::title { subcontrol-origin: margin; left: 16px; padding: 0 5px; color: #334D6E; }
QComboBox, QSpinBox { background: #F8FAFD; border: 1px solid #CDD8E6; border-radius: 6px; padding: 7px; min-height: 22px; }
QComboBox:disabled, QSpinBox:disabled { color: #99A5B6; background: #F3F5F8; }
QPushButton { background: #EDF2F8; border: 1px solid #D5DFEB; border-radius: 6px; padding: 9px 14px; color: #254569; font-weight: 600; }
QPushButton:hover { background: #DFEAF8; }
QPushButton:pressed { background: #CDDEF4; }
QPushButton:disabled { color: #A2AFBE; border-color: #E5EAF0; background: #F3F5F8; }
QPushButton#primary { background: #2468BB; border-color: #2468BB; color: white; }
QPushButton#primary:hover { background: #18559D; }
QPushButton#primary:disabled { background: #B6CAE2; border-color: #B6CAE2; }
QLabel#value { font-family: 'Segoe UI'; font-size: 47pt; font-weight: 700; color: #174C87; }
QLabel#muted { color: #718297; font-size: 9pt; }
QLabel#status { padding: 10px 12px; background: #EDF4FC; border-radius: 6px; }
QTableWidget { border: 0; background: white; alternate-background-color: #F6F8FC; gridline-color: #E8EDF4; selection-background-color: #DFECFD; selection-color: #172B4D; }
QHeaderView::section { background: #F0F4FA; color: #52677F; padding: 8px; border: 0; font-weight: 600; }
QSlider::groove:horizontal { height: 5px; background: #E0E7F1; border-radius: 2px; }
QSlider::sub-page:horizontal { background: #337FC9; border-radius: 2px; }
QSlider::handle:horizontal { width: 16px; margin: -6px 0; background: #2468BB; border: 2px solid white; border-radius: 8px; }
"""


class MainWindow(QMainWindow):
    def __init__(self, simulate=False, controller=None):
        super().__init__()
        self.controller = controller or DeviceController()
        self.records = deque(maxlen=1000)
        self.setWindowTitle("Sobel Control · FPGA 串口上位机")
        self.resize(1120, 790)
        self.setMinimumSize(930, 710)
        self.setStyleSheet(STYLE)
        root = QWidget(objectName="root")
        self.setCentralWidget(root)
        page = QVBoxLayout(root)
        page.setContentsMargins(25, 20, 25, 18)
        page.setSpacing(12)
        head = QHBoxLayout()
        titles = QVBoxLayout()
        titles.setSpacing(3)
        titles.addWidget(QLabel("Sobel Control", objectName="title"))
        titles.addWidget(QLabel("FPGA 边缘检测 · 串口阈值控制台", objectName="subtitle"))
        head.addLayout(titles)
        head.addStretch()
        head.addWidget(QLabel("协议 V1 · 第一版", objectName="badge"))
        page.addLayout(head)
        self.banner = QLabel(objectName="banner")
        self.banner.setWordWrap(True)
        page.addWidget(self.banner)

        top = QHBoxLayout()
        top.setSpacing(15)
        connection_box = QGroupBox("01  连接设备")
        connection_box.setMaximumWidth(400)
        form = QGridLayout(connection_box)
        form.setHorizontalSpacing(10)
        form.setVerticalSpacing(10)
        self.mode_combo = QComboBox()
        self.mode_combo.setObjectName("mode_combo")
        self.mode_combo.addItem("模拟设备（不连接硬件）", "sim")
        self.mode_combo.addItem("真实串口（FPGA）", "serial")
        self.mode_combo.setCurrentIndex(0 if simulate else 1)
        form.addWidget(QLabel("工作模式"), 0, 0)
        form.addWidget(self.mode_combo, 0, 1, 1, 2)
        self.port_combo = QComboBox()
        self.port_combo.setMinimumContentsLength(12)
        self.port_combo.setSizeAdjustPolicy(QComboBox.SizeAdjustPolicy.AdjustToMinimumContentsLengthWithIcon)
        self.port_combo.setToolTip("选择 Windows 已识别的 COM 口；打开前请关闭其他串口助手。")
        self.refresh_button = QPushButton("刷新")
        form.addWidget(QLabel("串口"), 1, 0)
        form.addWidget(self.port_combo, 1, 1)
        form.addWidget(self.refresh_button, 1, 2)
        self.baud_combo = QComboBox()
        for baud in (9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600):
            self.baud_combo.addItem(str(baud), baud)
        self.baud_combo.setCurrentText("115200")
        self.baud_combo.setToolTip("V1 建议初值 115200，必须与实际 FPGA 一致；固定 8N1、无流控。")
        form.addWidget(QLabel("波特率"), 2, 0)
        form.addWidget(self.baud_combo, 2, 1, 1, 2)
        self.scenario_combo = QComboBox()
        for title, key in [("正常响应", "normal"), ("无响应（测试超时）", "no_response"), ("拒绝设置", "reject_set"), ("接受但不生效", "no_apply")]:
            self.scenario_combo.addItem(title, key)
        self.scenario_label = QLabel("模拟场景")
        form.addWidget(self.scenario_label, 3, 0)
        form.addWidget(self.scenario_combo, 3, 1, 1, 2)
        self.connection_note = QLabel("8 数据位 · 无校验 · 1 停止位 · 无流控", objectName="muted")
        self.connection_note.setWordWrap(True)
        form.addWidget(self.connection_note, 4, 0, 1, 3)
        self.connect_button = QPushButton("连接设备", objectName="primary")
        self.ping_button = QPushButton("检查连接")
        form.addWidget(self.connect_button, 5, 0, 1, 2)
        form.addWidget(self.ping_button, 5, 2)
        top.addWidget(connection_box, 4)

        threshold_box = QGroupBox("02  设置与确认")
        threshold_layout = QVBoxLayout(threshold_box)
        threshold_layout.setSpacing(8)
        control_row = QHBoxLayout()
        value_col = QVBoxLayout()
        value_col.setSpacing(0)
        value_col.addWidget(QLabel("上次确认的有效阈值", objectName="muted"))
        self.value_label = QLabel("—", objectName="value")
        value_col.addWidget(self.value_label)
        self.source_label = QLabel("尚未读取设备", objectName="muted")
        value_col.addWidget(self.source_label)
        control_row.addLayout(value_col, 1)
        input_col = QVBoxLayout()
        input_col.addWidget(QLabel("待设置阈值   0–2047"))
        self.threshold_spin = QSpinBox()
        self.threshold_spin.setObjectName("threshold_spin")
        self.threshold_spin.setRange(0, 2047)
        self.threshold_spin.setValue(320)
        self.threshold_spin.setKeyboardTracking(False)
        self.threshold_spin.setToolTip("320 仅为界面初值，不代表真实 FPGA 的默认阈值。")
        input_col.addWidget(self.threshold_spin)
        self.threshold_slider = QSlider(Qt.Orientation.Horizontal)
        self.threshold_slider.setRange(0, 2047)
        self.threshold_slider.setValue(320)
        input_col.addWidget(self.threshold_slider)
        action_row = QHBoxLayout()
        self.set_button = QPushButton("设置阈值", objectName="primary")
        self.read_button = QPushButton("读取阈值")
        action_row.addWidget(self.set_button)
        action_row.addWidget(self.read_button)
        input_col.addLayout(action_row)
        control_row.addLayout(input_col, 2)
        threshold_layout.addLayout(control_row)
        steps = QHBoxLayout()
        self.step_labels = []
        for title in ("1  命令已发送", "2  设备已接受", "3  参数已生效"):
            label = QLabel(title)
            label.setAlignment(Qt.AlignmentFlag.AlignCenter)
            self.step_labels.append(label)
            steps.addWidget(label)
        threshold_layout.addLayout(steps)
        self.status_label = QLabel(objectName="status")
        self.status_label.setWordWrap(True)
        self.status_label.setMinimumHeight(51)
        threshold_layout.addWidget(self.status_label)
        top.addWidget(threshold_box, 7)
        page.addLayout(top)

        log_box = QGroupBox("03  收发记录")
        log_layout = QVBoxLayout(log_box)
        tools = QHBoxLayout()
        self.log_count = QLabel("最多保留最近 1000 条", objectName="muted")
        tools.addWidget(self.log_count)
        tools.addStretch()
        tools.addWidget(QLabel("字节显示"))
        self.log_format = QComboBox()
        self.log_format.addItems(["HEX", "ASCII 转义"])
        tools.addWidget(self.log_format)
        self.clear_button = QPushButton("清空")
        self.save_button = QPushButton("导出日志")
        tools.addWidget(self.clear_button)
        tools.addWidget(self.save_button)
        log_layout.addLayout(tools)
        self.log_table = QTableWidget(0, 4)
        self.log_table.setHorizontalHeaderLabels(["时间", "方向", "事件", "原始字节"])
        self.log_table.setAlternatingRowColors(True)
        self.log_table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        self.log_table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        self.log_table.verticalHeader().setVisible(False)
        self.log_table.setShowGrid(False)
        header = self.log_table.horizontalHeader()
        header.setSectionResizeMode(0, QHeaderView.ResizeMode.ResizeToContents)
        header.setSectionResizeMode(1, QHeaderView.ResizeMode.ResizeToContents)
        header.setSectionResizeMode(2, QHeaderView.ResizeMode.Stretch)
        header.setSectionResizeMode(3, QHeaderView.ResizeMode.Stretch)
        log_layout.addWidget(self.log_table)
        page.addWidget(log_box, 1)
        footer = QLabel("真实 FPGA 需实现新增协议 V1。模拟验证仅检查软件行为，不代表实板调参或图像效果已验证。", objectName="muted")
        footer.setWordWrap(True)
        page.addWidget(footer)

        self.mode_combo.currentIndexChanged.connect(self.render_state)
        self.refresh_button.clicked.connect(self.refresh_ports)
        self.connect_button.clicked.connect(self.toggle_connection)
        self.ping_button.clicked.connect(lambda: self.perform(self.controller.ping))
        self.read_button.clicked.connect(lambda: self.perform(self.controller.get_threshold))
        self.set_button.clicked.connect(lambda: self.perform(lambda: self.controller.set_threshold(self.threshold_spin.value())))
        self.threshold_spin.valueChanged.connect(self.threshold_slider.setValue)
        self.threshold_slider.valueChanged.connect(self.threshold_spin.setValue)
        self.clear_button.clicked.connect(self.clear_logs)
        self.save_button.clicked.connect(self.export_logs)
        self.log_format.currentIndexChanged.connect(self.rebuild_logs)
        self.refresh_ports()
        self.timer = QTimer(self)
        self.timer.setInterval(20)
        self.timer.timeout.connect(self.tick)
        self.timer.start()
        self.render_state()
        if simulate:
            QTimer.singleShot(0, self.toggle_connection)

    def refresh_ports(self):
        from serial.tools import list_ports
        previous = self.port_combo.currentData()
        self.port_combo.clear()
        try:
            for port in sorted(list_ports.comports(), key=lambda item: item.device):
                self.port_combo.addItem(f"{port.device} · {port.description}", port.device)
            if self.port_combo.count() == 0:
                self.port_combo.addItem("未发现串口，请连接开发板后刷新", None)
            elif previous:
                index = self.port_combo.findData(previous)
                if index >= 0:
                    self.port_combo.setCurrentIndex(index)
        except Exception as exc:
            self.port_combo.addItem("串口列表读取失败", None)
            self.add_record("ERROR", f"刷新串口失败：{exc}")
        self.render_state()

    def perform(self, action):
        try:
            action()
        except (RuntimeError, ValueError, OSError) as exc:
            self.add_record("ERROR", str(exc))
            self.controller.status = str(exc)
        self.render_state()

    def toggle_connection(self):
        if self.controller.connection != "disconnected":
            self.controller.disconnect()
        else:
            def connect():
                if self.mode_combo.currentData() == "sim":
                    transport = SimulatedTransport(scenario=self.scenario_combo.currentData())
                    self.controller.connect(transport, label="模拟设备 / " + self.scenario_combo.currentText(), simulated=True)
                else:
                    port = self.port_combo.currentData()
                    if not port:
                        raise ValueError("没有可用串口。可先切换到模拟设备体验软件。")
                    baud = self.baud_combo.currentData()
                    self.controller.connect(SerialTransport(port, baud), label=f"{port} / {baud} / 8N1", simulated=False)
            self.perform(connect)
        self.render_state()

    def tick(self):
        for event in self.controller.poll():
            self.add_record(event.kind, event.text, event.data)
        self.render_state()

    def render_state(self):
        c = self.controller
        sim = self.mode_combo.currentData() == "sim"
        disconnected = c.connection == "disconnected"
        available = c.connection == "connected" and c.pending is None
        self.mode_combo.setEnabled(disconnected)
        self.port_combo.setEnabled(disconnected and not sim)
        self.refresh_button.setEnabled(disconnected and not sim)
        self.baud_combo.setEnabled(disconnected and not sim)
        self.scenario_combo.setEnabled(disconnected and sim)
        self.scenario_combo.setVisible(sim)
        self.scenario_label.setVisible(sim)
        self.connect_button.setText("连接设备" if disconnected else "取消连接" if c.connection == "connecting" else "断开连接")
        self.connect_button.setEnabled(not disconnected or sim or self.port_combo.currentData() is not None)
        self.ping_button.setEnabled(available)
        self.read_button.setEnabled(available and c.verified)
        self.set_button.setEnabled(available and c.verified)
        self.threshold_spin.setEnabled(c.pending is None)
        self.threshold_slider.setEnabled(c.pending is None)
        if sim:
            self.banner.setText("模拟设备模式  ·  所有响应由软件生成，未连接真实 FPGA")
            self.banner.setStyleSheet("background: #FFF0CE; color: #825D13;")
        else:
            self.banner.setText("真实串口模式  ·  " + ("尚未连接设备" if disconnected else c.label) + "  ·  需匹配新增协议 V1")
            self.banner.setStyleSheet("background: #E6EFFB; color: #285B94;")
        self.setWindowTitle("Sobel Control · " + ("模拟设备（非实板）" if sim else "FPGA 串口上位机"))
        self.value_label.setText(str(c.active_threshold) if c.active_threshold is not None else "—")
        if c.active_threshold is None:
            self.source_label.setText("当前有效值未知，需连接后读取")
        elif c.uncertain:
            self.source_label.setText("仅为上次确认值 · 新设置结果待核实")
        else:
            self.source_label.setText("来源：" + ("模拟设备回执" if c.simulated else "设备回执") + " · 最新一次确认")
        is_set = c.operation == MessageType.SET_THRESHOLD
        for label, done in zip(self.step_labels, (c.command_sent, c.command_accepted, c.command_applied)):
            color = "background: #E5F4EE; color: #226F55;" if is_set and done else "background: #EFF2F6; color: #8694A5;"
            label.setStyleSheet(color + "padding: 9px 6px; border-radius: 5px; font-size: 9pt;")
        self.status_label.setText(c.status)

    def _bytes_text(self, data):
        if self.log_format.currentIndex() == 0:
            return data.hex(" ").upper()
        return "".join(chr(b) if 32 <= b <= 126 and b != 92 else f"\\x{b:02X}" for b in data)

    def add_record(self, kind, text, data=b""):
        record = (datetime.now().strftime("%H:%M:%S.%f")[:-3], "模拟" if self.mode_combo.currentData() == "sim" else "串口", kind, text, data)
        if len(self.records) == self.records.maxlen:
            self.log_table.removeRow(0)
        self.records.append(record)
        self._append_row(record)
        self.log_table.scrollToBottom()
        self.log_count.setText(f"{len(self.records)} 条记录 · 保留最近 1000 条")

    def _append_row(self, record):
        timestamp, mode, kind, text, data = record
        row = self.log_table.rowCount()
        self.log_table.insertRow(row)
        for column, content in enumerate((timestamp, kind, f"[{mode}] {text}", self._bytes_text(data))):
            item = QTableWidgetItem(content)
            item.setToolTip(content)
            self.log_table.setItem(row, column, item)

    def rebuild_logs(self):
        self.log_table.setRowCount(0)
        for record in self.records:
            self._append_row(record)

    def clear_logs(self):
        self.records.clear()
        self.log_table.setRowCount(0)
        self.log_count.setText("0 条记录 · 保留最近 1000 条")

    def export_logs(self):
        filename, _ = QFileDialog.getSaveFileName(self, "导出收发日志", "sobel_serial_log.csv", "CSV 日志 (*.csv)")
        if not filename:
            return
        try:
            with open(filename, "w", encoding="utf-8-sig", newline="") as file:
                writer = csv.writer(file)
                writer.writerow(["时间", "模式", "方向", "事件", "字节HEX"])
                for timestamp, mode, kind, text, data in self.records:
                    writer.writerow([timestamp, mode, kind, text, data.hex(" ").upper()])
        except OSError as exc:
            QMessageBox.warning(self, "导出失败", str(exc))
        else:
            self.add_record("INFO", f"日志已导出到 {filename}")

    def closeEvent(self, event):
        self.timer.stop()
        self.controller.disconnect()
        event.accept()
