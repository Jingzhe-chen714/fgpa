"""Run with: python -m sobel_host [--simulate]."""
import argparse
from pathlib import Path
import sys


def main():
    parser = argparse.ArgumentParser(description="Sobel FPGA 串口上位机")
    parser.add_argument("--simulate", action="store_true", help="启动并连接模拟设备（非真实 FPGA）")
    parser.add_argument("--screenshot", type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    try:
        from PySide6.QtCore import QTimer
        from PySide6.QtWidgets import QApplication
        from .gui import MainWindow
    except ImportError as exc:
        print(f"依赖尚未安装：{exc}\n请先运行 setup.bat。", file=sys.stderr)
        return 1
    app = QApplication(sys.argv[:1])
    app.setApplicationName("Sobel Control")
    app.setOrganizationName("FPGA Contest4")
    window = MainWindow(simulate=args.simulate)
    window.show()
    if args.screenshot:
        def capture():
            args.screenshot.parent.mkdir(parents=True, exist_ok=True)
            if not window.grab().save(str(args.screenshot)):
                print("截图保存失败", file=sys.stderr)
                app.exit(1)
            else:
                window.close()
        QTimer.singleShot(1000, capture)
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
