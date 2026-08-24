from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root = Path('/home/ubuntu/ffm-project/ffm-project/android/app/src/main/res')
sizes = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
}

font_candidates = [
    '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
    '/usr/share/fonts/truetype/liberation2/LiberationSans-Bold.ttf',
]
font_path = next((path for path in font_candidates if Path(path).exists()), None)

for folder, size in sizes.items():
    image = Image.new('RGBA', (size, size), (15, 56, 50, 255))
    draw = ImageDraw.Draw(image)
    margin = max(2, round(size * 0.08))
    draw.rounded_rectangle(
        (margin, margin, size - margin, size - margin),
        radius=max(4, round(size * 0.18)),
        fill=(24, 92, 82, 255),
        outline=(242, 174, 73, 255),
        width=max(1, round(size * 0.025)),
    )
    font_size = round(size * 0.38)
    font = ImageFont.truetype(font_path, font_size) if font_path else None
    text = 'FFM'
    box = draw.textbbox((0, 0), text, font=font)
    x = (size - (box[2] - box[0])) / 2 - box[0]
    y = (size - (box[3] - box[1])) / 2 - box[1] - size * 0.02
    draw.text((x, y), text, fill=(255, 255, 255, 255), font=font)
    image.save(root / folder / 'ic_launcher.png')
