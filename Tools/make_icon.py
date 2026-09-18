# Draws the app icon: a heavy slanted 75 over an ember bar on near black.
from PIL import Image, ImageDraw, ImageFont
S = 1024
img = Image.new("RGB", (S, S), (10, 10, 11))
layer = Image.new("L", (S, S), 0)
d = ImageDraw.Draw(layer)
font = ImageFont.truetype("C:/Windows/Fonts/ariblk.ttf", 560)
box = d.textbbox((0, 0), "75", font=font)
w, h = box[2] - box[0], box[3] - box[1]
d.text(((S - w) / 2 - box[0] - 34, (S - h) / 2 - box[1] - 60), "75", font=font, fill=255)
k = 0.2  # slant
layer = layer.transform((S, S), Image.AFFINE, (1, k, -k * S / 2, 0, 1, 0), resample=Image.BICUBIC)
img.paste((245, 245, 247), mask=layer)
bar = Image.new("L", (S, S), 0)
ImageDraw.Draw(bar).rounded_rectangle((302, 735, 826, 805), radius=35, fill=255)
bar = bar.transform((S, S), Image.AFFINE, (1, k, -k * S / 2, 0, 1, 0), resample=Image.BICUBIC)
img.paste((255, 90, 31), mask=bar)
img.save("App/Assets.xcassets/AppIcon.appiconset/icon.png")
