"""Run the case4 Golden Model over all downloaded images and synthetic patterns."""

from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parent
PY = sys.executable
IMAGE_DIR = ROOT / "images"
OUTPUT_DIR = ROOT / "outputs"


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for image_path in sorted(IMAGE_DIR.iterdir()):
        if image_path.suffix.lower() not in {".png", ".jpg", ".jpeg", ".tif", ".tiff"}:
            continue
        name = image_path.stem
        subprocess.run(
            [PY, str(ROOT / "golden_edge.py"), "--input", str(image_path), "--output-dir", str(OUTPUT_DIR / name / "no_median"), "--threshold", "320"],
            check=True,
        )
        subprocess.run(
            [PY, str(ROOT / "golden_edge.py"), "--input", str(image_path), "--output-dir", str(OUTPUT_DIR / name / "median"), "--threshold", "320", "--median"],
            check=True,
        )
    subprocess.run(
        [PY, str(ROOT / "golden_edge.py"), "--patterns-dir", str(OUTPUT_DIR / "patterns"), "--threshold", "320"],
        check=True,
    )
    print(f"Regression outputs written to {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
