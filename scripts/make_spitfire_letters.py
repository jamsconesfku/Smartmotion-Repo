"""Makes godot/assets/aircraft/spitfire_letters.png: the Spitfire's code letters and serial (MH434's 'ZD', 'B',
'MH434') as white shapes on a transparent background, one word per row. The paint shader (spitfire_paint.gdshader)
colours them (Sky for the codes, black for the serial) and places them on the fuselage.
Font: Barlow SemiBold (SIL Open Font Licence, in godot/assets/fonts), widened a little to the proportions of the
RAF's 1940s stencil-free code letters. Run: python3 -I scripts/make_spitfire_letters.py"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, "godot", "assets", "fonts", "Barlow-SemiBold.ttf")
OUT = os.path.join(ROOT, "godot", "assets", "aircraft", "spitfire_letters.png")
W, H = 1024, 256            # one row per word
WORDS = ["ZD", "B", "MH434"]
WIDEN = 1.18                # RAF code letters are broader than Barlow


def word(text):
    font = ImageFont.truetype(FONT, 300)
    box = font.getbbox(text)
    w, h = box[2] - box[0], box[3] - box[1]
    big = Image.new("L", (w + 40, h + 40), 0)
    ImageDraw.Draw(big).text((20 - box[0], 20 - box[1]), text, font=font, fill=255)
    big = big.crop(big.getbbox())
    tw = int(big.width * WIDEN * (H - 24) / big.height)
    return big.resize((min(tw, W - 24), H - 24), Image.LANCZOS)


img = Image.new("RGBA", (W, H * len(WORDS)), (255, 255, 255, 0))
for i, t in enumerate(WORDS):
    m = word(t)
    a = Image.new("L", (W, H), 0)
    a.paste(m, ((W - m.width) // 2, 12))   # centred in its row
    row = Image.new("RGBA", (W, H), (255, 255, 255, 255))
    row.putalpha(a)
    img.paste(row, (0, i * H))
    print(t, "width/height in its row:", round(m.width / m.height, 3))
img.save(OUT)
print("saved", OUT)
