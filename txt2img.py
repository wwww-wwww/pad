from PIL import Image, ImageDraw, ImageFont
import sys


def create_img(text, diff=True):
  font = ImageFont.truetype("arial.ttf", 15)
  w = 0
  for a in text:
    tw = font.getsize(a)[0]
    if tw > w:
      w = tw

  w += 4

  h = len(text) * 19
  img = Image.new("RGB", (w, h))

  d = ImageDraw.Draw(img)
  d.rectangle([0, 0, w, h], fill=(255, 255, 255))

  for k, v in enumerate(text):
    if diff and len(v) > 0:
      if v[0] == "-":
        d.rectangle([0, k * 19, w, k * 19 + 19], fill=(255, 230, 230))
      elif v[0] == "+":
        d.rectangle([0, k * 19, w, k * 19 + 19], fill=(220, 255, 220))
    d.text((2, 2 + k * 19), v, font=font, fill=(0, 0, 0))

  img.convert(mode="P")
  return img


if __name__ == "__main__":
  text = sys.argv[2].splitlines()
  create_img(text).save(sys.argv[1], format="webp", optimize=True)
