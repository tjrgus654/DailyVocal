"""Generates the app icon (1024x1024, no alpha) — dark navy gradient with a
cyan pitch-waveform motif matching the app's tracker design. Deterministic:
same output every run. Usage: python tools/gen_app_icon.py"""
from PIL import Image, ImageDraw
import math, os

SIZE = 1024
img = Image.new("RGB", (SIZE, SIZE))
draw = ImageDraw.Draw(img)

# Vertical gradient: #101838 (top) -> #06091C (bottom) — AppBackground tones.
top = (16, 24, 56)
bottom = (6, 9, 28)
for y in range(SIZE):
    t = y / (SIZE - 1)
    r = int(top[0] + (bottom[0] - top[0]) * t)
    g = int(top[1] + (bottom[1] - top[1]) * t)
    b = int(top[2] + (bottom[2] - top[2]) * t)
    draw.line([(0, y), (SIZE, y)], fill=(r, g, b))

def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

CYAN = (6, 182, 212)        # brandSecondary
WARM = (251, 146, 60)      # brandAccent
INDIGO = (99, 102, 241)    # brandPrimary

# Soft glow circles behind the wave (subtle depth, like the glass cards).
for cx, cy, radius, color, alpha in [
    (512, 430, 300, INDIGO, 0.10),
    (320, 560, 220, CYAN, 0.07),
    (720, 380, 200, WARM, 0.06),
]:
    overlay = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    od.ellipse([cx - radius, cy - radius, cx + radius, cy + radius],
               fill=color + (int(alpha * 255),))
    img = Image.alpha_composite(img.convert("RGBA"), overlay).convert("RGB")
    draw = ImageDraw.Draw(img)

# Pitch-trail waveform: vibrato-shaped sine with rising pitch offset — the
# app's core metaphor (live pitch trajectory). Drawn as a thick smooth line.
points = []
for x in range(90, SIZE - 90):
    t = (x - 90) / (SIZE - 180)
    base_y = 560 - 140 * t                    # rising pitch
    vibrato = 46 * math.sin(t * 2 * math.pi * 3.2) * (0.55 + 0.45 * t)
    jitter = 9 * math.sin(t * 2 * math.pi * 11)
    points.append((x, base_y + vibrato + jitter))

# Faint past trail (history ghost) in indigo, then the live line in cyan.
ghost = [(x, y + 26) for x, y in points]
draw.line(ghost, fill=lerp(INDIGO, (6, 9, 28), 0.35), width=14, joint="curve")
draw.line(points, fill=CYAN, width=22, joint="curve")

# Target line the trail approaches (dashed warm) — the "on pitch" reference.
for i in range(26):
    x0 = 120 + i * 32
    draw.line([(x0, 340), (min(x0 + 16, SIZE - 120), 340)],
              fill=WARM, width=8)

# Dot at the leading edge (the live note).
lx, ly = points[-1]
draw.ellipse([lx - 30, ly - 30, lx + 30, ly + 30], fill=CYAN)
draw.ellipse([lx - 12, ly - 12, lx + 12, ly + 12], fill=(255, 255, 255))

out_dir = os.path.join("Assets.xcassets", "AppIcon.appiconset")
os.makedirs(out_dir, exist_ok=True)
img.save(os.path.join(out_dir, "AppIcon.png"), "PNG")
print("icon written:", os.path.join(out_dir, "AppIcon.png"), img.size)
