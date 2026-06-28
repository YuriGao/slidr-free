#!/usr/bin/env python3
"""Generate a menu bar icon for Slidr-Free.

The icon represents trackpad edge sliding: two vertical bars (edges)
with up/down arrows between them. Designed as a template image
(black + alpha) for macOS menu bar.
"""

from PIL import Image, ImageDraw

SIZE = 44  # 2x retina for 22pt menubar icon
PADDING = 6
BAR_WIDTH = 4
BAR_HEIGHT = SIZE - PADDING * 2
ARROW_W = 12
ARROW_H = 6

img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

# Left edge bar
lx = PADDING
draw.rectangle(
    [lx, PADDING, lx + BAR_WIDTH - 1, PADDING + BAR_HEIGHT - 1], fill=(0, 0, 0, 255)
)

# Right edge bar
rx = SIZE - PADDING - BAR_WIDTH
draw.rectangle(
    [rx, PADDING, rx + BAR_WIDTH - 1, PADDING + BAR_HEIGHT - 1], fill=(0, 0, 0, 255)
)

# Center column
cx = SIZE // 2

# Up arrow (top half)
uy_top = PADDING + 2
draw.polygon(
    [
        (cx, uy_top),
        (cx - ARROW_W // 2, uy_top + ARROW_H),
        (cx + ARROW_W // 2, uy_top + ARROW_H),
    ],
    fill=(0, 0, 0, 255),
)

# Down arrow (bottom half)
dy_bottom = SIZE - PADDING - 2
draw.polygon(
    [
        (cx, dy_bottom),
        (cx - ARROW_W // 2, dy_bottom - ARROW_H),
        (cx + ARROW_W // 2, dy_bottom - ARROW_H),
    ],
    fill=(0, 0, 0, 255),
)

# Vertical line connecting arrows
line_w = 2
draw.rectangle(
    [cx - line_w // 2, uy_top + ARROW_H, cx + line_w // 2, dy_bottom - ARROW_H],
    fill=(0, 0, 0, 255),
)

img.save("Resources/MenuBarIcon.png")
print("Generated Resources/MenuBarIcon.png")
