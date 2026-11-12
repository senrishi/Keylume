"""Regenerate the committed app icons. Requires Pillow; no runtime dependency."""
from pathlib import Path
from PIL import Image, ImageDraw
root = Path(__file__).resolve().parent.parent
scale = 2
image = Image.new('RGBA', (1024 * scale, 1024 * scale))
draw = ImageDraw.Draw(image)
def box(coords, radius, fill, outline=None, width=1):
    draw.rounded_rectangle(tuple(int(v * scale * 2) for v in coords), int(radius * scale * 2), fill, outline, int(width * scale * 2))
box((24,24,488,488),112,'#0c1018')
box((72,68,440,436),80,'#1c2331','#3b465a',8)
draw.arc(tuple(int(v * scale * 2) for v in (112,337,400,400)),0,180,fill='#364257',width=8*scale*2)
for x,y,h,c in [(140,176,144,'#00d8ff'),(230,128,240,'#ff387d'),(320,160,176,'#c4f774')]:
    box((x,y,x+52,y+h),26,c)
image = image.resize((1024,1024),Image.Resampling.LANCZOS)
image.save(root/'branding/logo.png')
image.save(root/'branding/Keylume.ico',sizes=[(16,16),(24,24),(32,32),(48,48),(64,64),(128,128),(256,256)])
image.save(root/'branding/Keylume.icns')
image.resize((48,48),Image.Resampling.LANCZOS).save(root/'branding/tray.png')
print('Generated Keylume PNG, ICO, ICNS, and tray icon.')
