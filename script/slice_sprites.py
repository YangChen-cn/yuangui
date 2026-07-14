#!/usr/bin/env python3
"""Split the generated 4x2 sprite sheets into padded transparent PNG frames."""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SHEETS = ROOT / "Assets" / "Sprites" / "Sheets"

SPRITES = {
    "YuanGui": (
        "yuangui-actions.png",
        ["idle", "wave", "curious", "hop", "read", "system-meter", "yawn", "finger-heart"],
    ),
    "VCC": (
        "vcc-actions.png",
        ["loaf-idle", "paw-wave", "curious", "pounce", "belly-roll", "groom", "sleep", "alert"],
    ),
    "Duo": (
        "duo-actions.png",
        ["idle", "pet", "cuddle", "wave", "read", "play", "alert", "hug"],
    ),
}


def split_sheet(folder: str, sheet_name: str, actions: list[str]) -> None:
    source = Image.open(SHEETS / sheet_name).convert("RGBA")
    output_dir = ROOT / "Assets" / "Sprites" / folder
    output_dir.mkdir(parents=True, exist_ok=True)

    x_edges = [round(source.width * column / 4) for column in range(5)]
    y_edges = [round(source.height * row / 2) for row in range(3)]

    for index, action in enumerate(actions):
        column = index % 4
        row = index // 4
        frame = source.crop(
            (x_edges[column], y_edges[row], x_edges[column + 1], y_edges[row + 1])
        )
        canvas = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
        origin = ((512 - frame.width) // 2, (512 - frame.height) // 2)
        canvas.alpha_composite(frame, origin)
        canvas.save(output_dir / f"{index + 1:02d}-{action}.png", optimize=True)


if __name__ == "__main__":
    for destination, (sheet, frame_actions) in SPRITES.items():
        split_sheet(destination, sheet, frame_actions)
