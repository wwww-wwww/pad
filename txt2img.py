from PIL import Image, ImageDraw, ImageFont
import sys
import json


def create_img(j, diff=True):
  font = ImageFont.truetype("arial.ttf", 15)

  if len(j[0]) > 1:
    j[0][1] = "\n".join(j[0][1].split("\n")[-4:])
    if j[0] != j[-1]:
      j[-1][1] = "\n".join(j[-1][1].split("\n")[:3])

  emptylines = []

  lc = 0

  for l in j:
    lines = l[1].count("\n")
    if l[0] == "equal":
      if lines > 7:
        l[1] = l[1].split("\n")[:3] + [""] + l[1].split("\n")[-3:]
        l[1] = "\n".join(l[1])
        emptylines += [lc + 4]
    lc += lines

  w = 0
  h = 1
  tw = 0
  for l in j:
    for c in l[1]:
      if c == "\n":
        tw = 0
        h += 1
        continue
      tw += font.getbbox(c)[2]
      if tw > w:
        w = tw

  w += 4

  h *= 19
  img = Image.new("RGB", (w, h))

  d = ImageDraw.Draw(img)
  d.rectangle([0, 0, w, h], fill=(255, 255, 255))

  x = 0
  y = 0

  for l in j:
    for c in l[1]:
      if c == "\n":
        if x == 0:
          if l[0] == "insert":
            d.rectangle([0, (y) * 19, w, (y) * 19 + 19], fill=(220, 255, 220))
          elif l[0] == "delete":
            d.rectangle([0, (y) * 19, w, (y) * 19 + 19], fill=(255, 220, 220))
          elif y in emptylines:
            d.rectangle([0, (y - 1) * 19, w, (y - 1) * 19 + 19],
                        fill=(230, 230, 230))
        else:
          if l[0] == "insert":
            d.rectangle([0, (y + 1) * 19, w, (y + 1) * 19 + 19],
                        fill=(220, 255, 220))
          elif l[0] == "delete":
            d.rectangle([0, (y + 1) * 19, w, (y + 1) * 19 + 19],
                        fill=(255, 220, 220))
          elif y in emptylines:
            d.rectangle([0, (y - 1) * 19, w, (y - 1) * 19 + 19],
                        fill=(230, 230, 230))
        x = 0
        y += 1
        continue
      bbox = font.getbbox(c)
      if l[0] == "insert":
        d.rectangle([x, y * 19, x + bbox[2] + 2, y * 19 + 19],
                    fill=(220, 255, 220))
      elif l[0] == "delete":
        d.rectangle([x, y * 19, x + bbox[2] + 2, y * 19 + 19],
                    fill=(255, 220, 220))
      x += bbox[2]

  x = 0
  y = 0

  for l in j:
    for c in l[1]:
      if c == "\n":
        x = 0
        y += 19
        continue
      bbox = font.getbbox(c)
      d.text((2 + x, 2 + y), c, font=font, fill=(0, 0, 0))
      x += bbox[2]

  img.convert(mode="P")
  return img


if __name__ == "__main__":
  j = json.loads(sys.argv[2])
  create_img(j).save(sys.argv[1], format="webp", optimize=True)
  #j = json.loads(text)
  #create_img(j).save("test.webp", format="webp", optimize=True)
