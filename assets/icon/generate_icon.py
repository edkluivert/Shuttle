from PIL import Image, ImageDraw, ImageFilter, ImageChops

S, SS = 1024, 4
C = S * SS
U = C / 1024.0

BG_TOP = (0x9A, 0x7F, 0xFF)
BG_BOT = (0x46, 0x28, 0xC8)
INK    = (0xFF, 0xFF, 0xFF, 255)
MINT   = (0x2D, 0xD4, 0xA7, 255)

def squircle_mask(inset, radius):
    m = Image.new('L', (C, C), 0)
    ImageDraw.Draw(m).rounded_rectangle(
        [inset, inset, C - inset, C - inset], radius=radius, fill=255)
    return m

def diagonal_gradient():
    small = 256
    g = Image.new('RGB', (small, small))
    px = g.load()
    for y in range(small):
        for x in range(small):
            t = (x / small) * 0.35 + (y / small) * 0.65
            px[x, y] = tuple(int(BG_TOP[i] + (BG_BOT[i] - BG_TOP[i]) * t) for i in range(3))
    return g.resize((C, C), Image.BICUBIC).convert('RGBA')

def base_plate():
    inset = int(C * 0.098)
    radius = int((C - 2 * inset) * 0.2237)
    mask = squircle_mask(inset, radius)

    canvas = Image.new('RGBA', (C, C), (0, 0, 0, 0))

    sh = Image.new('L', (C, C), 0)
    ImageDraw.Draw(sh).rounded_rectangle(
        [inset, inset + int(C * 0.014), C - inset, C - inset + int(C * 0.014)],
        radius=radius, fill=110)
    sh = sh.filter(ImageFilter.GaussianBlur(C * 0.015))
    shadow = Image.new('RGBA', (C, C), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 255), (0, 0, C, C), sh)
    canvas = Image.alpha_composite(canvas, shadow)

    plate = Image.new('RGBA', (C, C), (0, 0, 0, 0))
    plate.paste(diagonal_gradient(), (0, 0), mask)
    canvas = Image.alpha_composite(canvas, plate)

    sheen = Image.new('RGBA', (C, C), (0, 0, 0, 0))
    ImageDraw.Draw(sheen).ellipse(
        [-C * 0.25, -C * 0.55, C * 0.95, C * 0.5], fill=(255, 255, 255, 38))
    sheen = sheen.filter(ImageFilter.GaussianBlur(C * 0.03))
    sheen.putalpha(ImageChops.multiply(sheen.split()[3], mask))
    canvas = Image.alpha_composite(canvas, sheen)
    return canvas

def arrow(d, cx, cy, h, shaft_w, head_w, head_h, color, up=True):
    top, bot, r = cy - h / 2, cy + h / 2, shaft_w / 2
    if up:
        d.rounded_rectangle([cx - r, top + head_h * 0.6, cx + r, bot], radius=r * 0.8, fill=color)
        d.polygon([(cx, top), (cx - head_w / 2, top + head_h), (cx + head_w / 2, top + head_h)], fill=color)
    else:
        d.rounded_rectangle([cx - r, top, cx + r, bot - head_h * 0.6], radius=r * 0.8, fill=color)
        d.polygon([(cx, bot), (cx - head_w / 2, bot - head_h), (cx + head_w / 2, bot - head_h)], fill=color)

def candidate_a():
    img = base_plate(); d = ImageDraw.Draw(img)
    h, sw, hw, hh = 500*U, 116*U, 276*U, 202*U
    arrow(d, C/2 - 162*U, C/2 - 32*U, h, sw, hw, hh, MINT, up=True)
    arrow(d, C/2 + 162*U, C/2 + 32*U, h, sw, hw, hh, INK,  up=False)
    return img

def candidate_b():
    img = base_plate(); d = ImageDraw.Draw(img)
    def device(cx, cy, w, hgt):
        d.rounded_rectangle([cx-w/2, cy-hgt/2, cx+w/2, cy+hgt/2],
                            radius=34*U, width=int(30*U), outline=INK)
    device(C/2 - 268*U, C/2, 210*U, 320*U)
    device(C/2 + 268*U, C/2, 210*U, 320*U)
    d.rounded_rectangle([C/2-118*U, C/2-30*U, C/2+52*U, C/2+30*U], radius=30*U, fill=MINT)
    d.polygon([(C/2+150*U, C/2), (C/2+40*U, C/2-102*U), (C/2+40*U, C/2+102*U)], fill=MINT)
    return img

def candidate_c():
    img = base_plate(); d = ImageDraw.Draw(img)
    cx, cy = C/2, C/2 + 150*U
    for i, rr in enumerate((340, 232, 124)):
        d.arc([cx-rr*U, cy-rr*U, cx+rr*U, cy+rr*U], start=207, end=333,
              fill=(MINT if i == 2 else INK), width=int(74*U))
    d.ellipse([cx-50*U, cy-50*U, cx+50*U, cy+50*U], fill=INK)
    return img

def candidate_d():
    """Arrows crossing on a diagonal — up-right mint, down-left white."""
    img = base_plate()
    lay = Image.new('RGBA', (C, C), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    h, sw, hw, hh = 500*U, 112*U, 268*U, 196*U
    arrow(d, C/2, C/2 - 150*U, h, sw, hw, hh, MINT, up=True)
    arrow(d, C/2, C/2 + 150*U, h, sw, hw, hh, INK,  up=False)
    lay = lay.rotate(-38, resample=Image.BICUBIC, center=(C/2, C/2))
    return Image.alpha_composite(img, lay)

CANDS = {'a': candidate_a, 'b': candidate_b, 'c': candidate_c, 'd': candidate_d}

if __name__ == '__main__':
    for name, fn in CANDS.items():
        im = fn().resize((S, S), Image.LANCZOS)
        im.save(f'/tmp/iconwork/cand_{name}_1024.png')
        for sz in (128, 32, 16):
            im.resize((sz, sz), Image.LANCZOS).save(f'/tmp/iconwork/cand_{name}_{sz}.png')
    print('done')
