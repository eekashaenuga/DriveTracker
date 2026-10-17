"""Deterministic approved-master exports. Requires Pillow and numpy; no AI/redrawing."""
from pathlib import Path
import hashlib
import json
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "android/app/src/main/res"
MASTER = ROOT / "assets/branding/source/Vehnora-V-Master.png"
BACKGROUND = (0, 87, 79, 255)  # @color/brand_launcher_background
im = Image.open(MASTER).convert("RGBA")
a = im.getchannel("A")
visible = a.point(lambda x: 255 if x > 8 else 0).getbbox()
assert visible is not None
# Trim surrounding near-invisible dust, retaining four pixels around visible edges.
box = (max(0, visible[0]-4), max(0, visible[1]-4),
       min(im.width, visible[2]+4), min(im.height, visible[3]+4))
mark = im.crop(box)
y, x = np.nonzero(np.asarray(mark.getchannel("A")) > 8)
cx, cy = mark.width/2, mark.height/2
radius = np.sqrt((x-cx)**2+(y-cy)**2).max()
outputs = {}

def save(image, path):
    path = ROOT / path
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, optimize=True)
    outputs[str(path.relative_to(ROOT)).replace("\\", "/")] = {
        "size": list(image.size), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}

def render(source, size, fraction):
    scale = size*fraction/radius
    dimensions = (round(mark.width*scale), round(mark.height*scale))
    # Premultiplied-alpha Lanczos avoids introducing dark resize halos.
    scaled = source.convert("RGBa").resize(dimensions, Image.Resampling.LANCZOS).convert("RGBA")
    canvas = Image.new("RGBA", (size, size))
    canvas.alpha_composite(scaled, ((size-scaled.width)//2, (size-scaled.height)//2))
    return canvas

foreground = render(mark, 432, 32/108)
save(foreground, "android/app/src/main/res/drawable-xxxhdpi/vehnora_launcher_foreground.png")
# Monochrome alone is simplified, directly from source alpha and neutral road pixels.
pixels = np.asarray(mark)
mask = np.where(pixels[:,:,3] > 128, 255, 0).astype("uint8")
rgb = pixels[:,:,:3].astype("int16")
road = (rgb.min(axis=2) > 180) & ((rgb.max(axis=2)-rgb.min(axis=2)) < 28)
# Fill tiny alpha pinholes in the silhouette before retaining intentional road gaps.
flood = Image.fromarray(mask).copy()
ImageDraw.floodfill(flood, (0,0), 255)
mask = np.maximum(mask, 255-np.asarray(flood))
road[:, :round(mark.width*0.42)] = False
mask[road] = 0
mono = Image.new("RGBA", mark.size, (255,255,255,0))
mono.putalpha(Image.fromarray(mask))
save(render(mono,432,32/108), "android/app/src/main/res/drawable-xxxhdpi/vehnora_launcher_monochrome.png")
save(render(mark,1152,90/288), "android/app/src/main/res/drawable-xxxhdpi/vehnora_splash.png")
for density, size in [("mdpi",48),("hdpi",72),("xhdpi",96),("xxhdpi",144),("xxxhdpi",192)]:
    canvas = Image.new("RGBA", (size,size), BACKGROUND)
    canvas.alpha_composite(render(mark,size,0.40))
    save(canvas, f"android/app/src/main/res/mipmap-{density}/ic_launcher.png")
for folder, size in [("",64),("2.0x/",128),("3.0x/",192)]:
    save(render(mark,size,0.45), f"assets/branding/flutter/{folder}vehnora_mark.png")

# Visual QA on actual launcher masks and both splash surfaces.
sheet = Image.new("RGB", (960,640), "#e7eae8")
draw = ImageDraw.Draw(sheet)
for index, shape in enumerate(["Circle", "Squircle", "Rounded square"]):
    size=240
    canvas=Image.new("RGBA",(size,size),BACKGROUND)
    canvas.alpha_composite(render(mark,size,32/72))
    clip=Image.new("L",(size,size)); d=ImageDraw.Draw(clip)
    if shape=="Circle": d.ellipse((0,0,size-1,size-1),fill=255)
    elif shape=="Rounded square": d.rounded_rectangle((0,0,size-1,size-1),radius=48,fill=255)
    else:
        yy,xx=np.mgrid[0:size,0:size]
        clip=Image.fromarray(np.where(abs((xx+0.5-size/2)/(size/2))**4 +
            abs((yy+0.5-size/2)/(size/2))**4 <=1,255,0).astype("uint8"))
    # All visible artwork survives every mask at these preview sizes.
    aa=np.asarray(render(mark,size,32/72).getchannel("A"))
    assert not np.any((aa>8)&(np.asarray(clip)==0))
    canvas.putalpha(clip)
    sheet.paste(canvas,(index*320+40,30),canvas)
    draw.text((index*320+40,280),shape,fill="black")
for index, color in enumerate(["#F7FAF8","#0D1715"]):
    canvas=Image.new("RGBA",(240,240),color)
    canvas.alpha_composite(render(mark,240,90/288))
    sheet.paste(canvas,(index*320+40,340))
    draw.text((index*320+40,590),"Native splash: "+color,fill="black")
canvas=Image.new("RGBA",(240,240),"#ddeee8")
tinted=Image.new("RGBA",(240,240),"#143e35")
tinted.putalpha(render(mono,240,32/72).getchannel("A"))
canvas.alpha_composite(tinted)
sheet.paste(canvas,(680,340))
draw.text((680,590),"Themed silhouette (tinted preview)",fill="black")
save(sheet,"assets/branding/android/brand_qa.png")
report={"master_sha256":hashlib.sha256(MASTER.read_bytes()).hexdigest(),
        "master_size":list(im.size),"alpha_visible_threshold":8,
        "visible_bounds":list(visible),"crop_bounds":list(box),"outputs":outputs}
(ROOT/"assets/branding/android/asset_manifest.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
print(json.dumps({k:v for k,v in report.items() if k!="outputs"},indent=2))
print(f"Generated {len(outputs)} exports; launcher mask containment passed.")
