"""Offscreen interaction checks; all devices in these tests are simulated."""
from __future__ import annotations

import os
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

import time
import unittest
from unittest.mock import patch

from PySide6.QtCore import Qt
from PySide6.QtTest import QTest
from PySide6.QtWidgets import QApplication

from sobel_host.controller import DeviceController
from sobel_host.gui import MainWindow


class GuiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QApplication.instance() or QApplication([])

    def setUp(self):
        self.controller = DeviceController(response_timeout=0.3, apply_timeout=0.4)
        with patch("serial.tools.list_ports.comports", return_value=[]):
            self.window = MainWindow(controller=self.controller)
        self.window.show()
        self.app.processEvents()

    def tearDown(self):
        self.window.close()
        worker = self.controller._worker
        if worker:
            worker.join(timeout=1)
            self.assertFalse(worker.is_alive())
        self.window.deleteLater()
        self.app.processEvents()

    def wait_for(self, predicate, timeout=2):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            self.app.processEvents()
            if predicate():
                return
            QTest.qWait(5)
        self.fail(f"UI condition timed out: {self.controller.status}")

    def click(self, button):
        self.assertTrue(button.isEnabled())
        QTest.mouseClick(button, Qt.MouseButton.LeftButton)

    def connect_simulated(self, scenario="normal"):
        self.window.mode_combo.setCurrentIndex(self.window.mode_combo.findData("sim"))
        self.window.scenario_combo.setCurrentIndex(self.window.scenario_combo.findData(scenario))
        self.click(self.window.connect_button)
        self.wait_for(lambda: self.controller.stage == "readback")
        self.assertEqual(self.window.value_label.text(), "320")
        self.assertIn("模拟", self.window.banner.text())
        self.assertIn("未连接真实 FPGA", self.window.banner.text())
        self.assertIn("模拟", self.window.windowTitle())
        self.assertFalse(self.window.mode_combo.isEnabled())

    def test_mock_set_readback_disconnect_through_buttons(self):
        self.assertFalse(self.window.connect_button.isEnabled(), "No COM port should not connect")
        self.assertFalse(self.window.set_button.isEnabled())
        self.connect_simulated()
        self.window.threshold_spin.setValue(512)
        self.click(self.window.set_button)
        self.wait_for(lambda: self.controller.stage == "accepted")
        self.assertFalse(self.window.set_button.isEnabled())
        self.assertFalse(self.window.read_button.isEnabled())
        self.assertEqual(self.window.value_label.text(), "320")
        self.assertIn("待核实", self.window.source_label.text())
        self.assertIn("#226F55", self.window.step_labels[1].styleSheet())
        self.assertNotIn("#226F55", self.window.step_labels[2].styleSheet())

        self.wait_for(lambda: self.controller.stage == "applied")
        self.assertEqual(self.window.value_label.text(), "512")
        self.assertIn("模拟设备回执", self.window.source_label.text())
        self.assertIn("#226F55", self.window.step_labels[2].styleSheet())
        self.click(self.window.read_button)
        self.wait_for(lambda: self.controller.stage == "readback")
        self.assertEqual(self.window.value_label.text(), "512")
        self.assertGreater(self.window.log_table.rowCount(), 0)
        self.assertTrue(any(record[2] == "TX" for record in self.window.records))
        self.assertTrue(any(record[2] == "RX" for record in self.window.records))
        self.assertTrue(all(record[1] == "模拟" for record in self.window.records))

        self.click(self.window.connect_button)
        self.assertEqual(self.window.value_label.text(), "—")
        self.assertFalse(self.window.set_button.isEnabled())
        self.assertTrue(self.window.mode_combo.isEnabled())

    def test_no_apply_scenario_shows_unknown_after_acceptance_timeout(self):
        self.controller.apply_timeout = 0.12
        self.connect_simulated("no_apply")
        self.window.threshold_spin.setValue(2047)
        self.click(self.window.set_button)
        self.wait_for(lambda: self.controller.stage == "accepted")
        self.assertEqual(self.window.value_label.text(), "320")
        self.assertFalse(self.controller.command_applied)
        self.wait_for(lambda: self.controller.stage == "timeout")
        self.assertEqual(self.window.value_label.text(), "—")
        self.assertIn("未收到生效确认", self.window.status_label.text())
        self.assertIn("不会自动重发", self.window.status_label.text())
        self.assertNotIn("#226F55", self.window.step_labels[2].styleSheet())
        self.assertTrue(self.window.read_button.isEnabled())

    def test_no_response_scenario_never_enables_threshold_controls(self):
        self.window.mode_combo.setCurrentIndex(self.window.mode_combo.findData("sim"))
        self.window.scenario_combo.setCurrentIndex(self.window.scenario_combo.findData("no_response"))
        self.click(self.window.connect_button)
        self.wait_for(lambda: self.controller.stage == "timeout")
        self.assertFalse(self.controller.verified)
        self.assertFalse(self.window.set_button.isEnabled())
        self.assertFalse(self.window.read_button.isEnabled())
        self.assertTrue(self.window.ping_button.isEnabled())
        self.assertEqual(self.window.value_label.text(), "—")
        self.assertIn("超时", self.window.status_label.text())


if __name__ == "__main__":
    unittest.main()
