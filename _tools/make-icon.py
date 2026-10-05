"""Derive the Raycast extension icon from the installed DeepSeek Harness app icon.

The extension is a companion to the DSH desktop app, so it wears the same mark: the app's own
1024px icon, resampled to the 512px square Raycast expects. That asset already carries an alpha
channel with transparent corners and margin, so it composites cleanly on any theme.

Usage:
    python _tools/make-icon.py [path-to-app-icon]
"""

import os
import sys

from PIL import Image

SIZE = 512
DEFAULT_SOURCES = (
    os.path.join(
        os.environ.get("LOCALAPPDATA", ""),
        "Programs",
        "DeepSeek Harness",
        "resources",
        "icon.png",
    ),
    os.path.join(
        os.environ.get("ProgramFiles", r"C:\Program Files"),
        "DeepSeek Harness",
        "resources",
        "icon.png",
    ),
)
OUTPUT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "assets",
    "extension-icon.png",
)


def find_source() -> str:
    if len(sys.argv) > 1:
        return sys.argv[1]
    for candidate in DEFAULT_SOURCES:
        if candidate and os.path.isfile(candidate):
            return candidate
    raise SystemExit(
        "The DeepSeek Harness app icon was not found. Pass its path explicitly, for example:\n"
        r"  python _tools/make-icon.py 'C:\path\to\resources\icon.png'"
    )


def main() -> None:
    source = find_source()
    with Image.open(source) as image:
        icon = image.convert("RGBA")

    if icon.width != icon.height:
        raise SystemExit(f"the app icon is not square: {icon.size}")

    icon = icon.resize((SIZE, SIZE), Image.LANCZOS)
    icon.save(OUTPUT)
    print(f"wrote {OUTPUT} ({SIZE}x{SIZE}) from {source}")


if __name__ == "__main__":
    main()
