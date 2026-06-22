"""
Renders the Octet app mark (Mark D — four cells) at any size.
Brand colors: honey #E89A2B, cream #FFFCF5, ink #1F1B16.
Proportions match the approved concept: cells occupy ~26% width, ~69% height,
4 cells with gaps, bottom cell = accent.
"""
from PIL import Image, ImageDraw

HONEY = (232, 154, 43)
CREAM = (255, 252, 245)
INK   = (31, 27, 22)

def draw_mark(size, bg, cell, accent, rounded=False, pad_frac=0.0):
    # Supersample 4x for crisp edges, then downscale.
    ss = 4
    S = size * ss
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Optional transparent padding (macOS-style). pad_frac of full size each side.
    pad = int(S * pad_frac)
    inner = S - 2 * pad
    x0, y0 = pad, pad

    # Tile
    if rounded:
        r = int(inner * 0.2237)  # iOS squircle-ish radius
        d.rounded_rectangle([x0, y0, x0 + inner, y0 + inner], radius=r, fill=bg)
    else:
        d.rectangle([x0, y0, x0 + inner, y0 + inner], fill=bg)

    # Four cells, centered in the inner tile.
    cell_w = inner * 0.262
    cell_h = inner * 0.137
    gap    = inner * 0.046
    total_h = 4 * cell_h + 3 * gap
    cx = x0 + inner / 2
    top = y0 + (inner - total_h) / 2
    rx = cell_h * 0.28
    for i in range(4):
        cy = top + i * (cell_h + gap)
        col = accent if i == 3 else cell
        d.rounded_rectangle(
            [cx - cell_w / 2, cy, cx + cell_w / 2, cy + cell_h],
            radius=rx, fill=col,
        )

    return img.resize((size, size), Image.LANCZOS)

def render_macos(outdir):
    """Rounded squircle + 10% transparent padding, at every macOS pixel size."""
    import os
    os.makedirs(outdir, exist_ok=True)
    for px in (16, 32, 64, 128, 256, 512, 1024):
        img = draw_mark(px, HONEY, CREAM, INK, rounded=True, pad_frac=0.10)
        img.save(os.path.join(outdir, f"icon_{px}.png"))   # keep alpha (padding)
    print(f"rendered macOS sizes into {outdir}: " + ", ".join(f"icon_{p}.png" for p in (16,32,64,128,256,512,1024)))


if __name__ == "__main__":
    import sys
    if len(sys.argv) >= 2 and sys.argv[1] == "--macos":
        # Usage: render_icon.py --macos <output-dir>
        render_macos(sys.argv[2] if len(sys.argv) >= 3 else ".")
    else:
        # iOS production asset: full-bleed square, opaque, NO rounded corners
        # (iOS applies the mask itself). Honey colorway.
        ios = draw_mark(1024, HONEY, CREAM, INK, rounded=False)
        ios.convert("RGB").save("Octet-iOS-1024.png")

        # Viewing preview: rounded, so you see what users actually see.
        prev = draw_mark(512, HONEY, CREAM, INK, rounded=True)
        prev.save("Octet-preview-rounded.png")

        # Dark colorway preview (alt).
        darkp = draw_mark(512, INK, CREAM, HONEY, rounded=True)
        darkp.save("Octet-preview-dark.png")

        print("rendered: Octet-iOS-1024.png, Octet-preview-rounded.png, Octet-preview-dark.png")
