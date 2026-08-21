"""Regenerates the installer artwork: window background and volume icon.

    python3 packaging/generate_dmg_assets.py

Needs Pillow. The volume icon is built from assets/icon/app_icon.png, so the
installer and the app always carry the same mark.
"""
import os
import subprocess
import tempfile

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

APP_NAME = 'Shuttle'
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
MASTER = os.path.join(ROOT, 'assets', 'icon', 'app_icon.png')

W, H, SS = 660, 420, 2          # window size in points; SS gives the @2x image
ACCENT = (0x7C, 0x5C, 0xFF)
BG_TOP, BG_BOT = (0x0B, 0x0C, 0x11), (0x18, 0x14, 0x28)
GLOW = (0x2E, 0x1E, 0x6E)


def _font(size):
    for path in ('/System/Library/Fonts/SFNS.ttf',
                 '/System/Library/Fonts/HelveticaNeue.ttc'):
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def background():
    w, h = W * SS, H * SS
    img = Image.new('RGB', (w, h))
    px = img.load()
    for y in range(h):
        t = y / h
        row = tuple(int(BG_TOP[i] + (BG_BOT[i] - BG_TOP[i]) * t) for i in range(3))
        for x in range(w):
            px[x, y] = row

    glow = Image.new('RGB', (w, h), (0, 0, 0))
    ImageDraw.Draw(glow).ellipse(
        [int(w * 0.18), int(h * 0.18), int(w * 0.82), int(h * 0.92)], fill=GLOW)
    img = ImageChops.add(img, glow.filter(ImageFilter.GaussianBlur(w * 0.09))
                              .point(lambda v: int(v * 0.75)))

    d = ImageDraw.Draw(img)

    def centred(text, y, font, fill):
        bb = d.textbbox((0, 0), text, font=font)
        d.text(((w - (bb[2] - bb[0])) / 2 - bb[0], y), text, font=font, fill=fill)

    centred(APP_NAME, int(h * 0.09), _font(21 * SS), (0xF2, 0xF3, 0xF8))
    centred('Drag the app onto the Applications folder', int(h * 0.855),
            _font(12 * SS), (0x8C, 0x92, 0xA8))

    # The arrow sits between where the two icons are placed by build_dmg.sh.
    cy = int(h * 0.47)
    x0, x1 = int(w * 0.455), int(w * 0.545)
    d.rounded_rectangle([x0, cy - 3 * SS, x1 - 13 * SS, cy + 3 * SS],
                        radius=3 * SS, fill=ACCENT)
    d.polygon([(x1, cy), (x1 - 22 * SS, cy - 13 * SS), (x1 - 22 * SS, cy + 13 * SS)],
              fill=ACCENT)

    img.save(os.path.join(HERE, 'dmg_background@2x.png'))
    img.resize((W, H), Image.LANCZOS).save(os.path.join(HERE, 'dmg_background.png'))


def volume_icon():
    src = Image.open(MASTER)
    with tempfile.TemporaryDirectory() as tmp:
        iconset = os.path.join(tmp, 'vol.iconset')
        os.mkdir(iconset)
        for px, name in [(16, '16x16'), (32, '16x16@2x'), (32, '32x32'),
                         (64, '32x32@2x'), (128, '128x128'), (256, '128x128@2x'),
                         (256, '256x256'), (512, '256x256@2x'), (512, '512x512'),
                         (1024, '512x512@2x')]:
            im = src if px == src.width else src.resize((px, px), Image.LANCZOS)
            im.save(os.path.join(iconset, f'icon_{name}.png'))
        subprocess.run(['iconutil', '-c', 'icns', iconset,
                        '-o', os.path.join(HERE, 'VolumeIcon.icns')], check=True)


if __name__ == '__main__':
    background()
    volume_icon()
    print(f'wrote dmg_background.png, dmg_background@2x.png, VolumeIcon.icns for "{APP_NAME}"')
