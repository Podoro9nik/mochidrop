"""Export the approved Mochi courier artwork. Requires CairoSVG and Pillow."""

from pathlib import Path
import json
import shutil
import struct
import zipfile

import cairosvg
from PIL import Image


ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'design' / 'icon'
APPICON = ROOT / 'MochiDrop' / 'Assets.xcassets' / 'AppIcon.appiconset'
SIZES = (16, 20, 24, 32, 40, 48, 64, 96, 128, 256, 512, 1024)
ICO_SIZES = SIZES[:-2]
CAT = 'M56 108V61Q56 47 68 53L95 80Q128 70 161 80L188 53Q200 47 200 61V108C209 122 214 137 214 153C214 190 176 217 128 217C80 217 42 190 42 153C42 137 47 122 56 108Z'
EYES = 'M82 123C82 115 88 109 96 109C104 109 110 115 110 123H101C101 116 91 116 91 123Z M146 123C146 115 152 109 160 109C168 109 174 115 174 123H165C165 116 155 116 155 123Z'
ARROW = 'M120 148Q120 144 124 144H132Q136 144 136 148V163H151Q155 163 152 167L131 188Q128 191 125 188L104 167Q101 163 105 163H120Z'
SMALL_EYES = 'M76 126C76 114 84 104 96 104C108 104 116 114 116 126H102C102 116 90 116 90 126Z M140 126C140 114 148 104 160 104C172 104 180 114 180 126H166C166 116 154 116 154 126Z'
SMALL_ARROW = 'M116 148Q116 144 120 144H136Q140 144 140 148V161H156Q162 161 158 166L132 192Q128 196 124 192L98 166Q94 161 100 161H116Z'


def svg(title, body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256" role="img" aria-labelledby="title"><title id="title">{title}</title>{body}</svg>\n'


def icon(small=False, flat=False):
    surface = '<rect x="12" y="10" width="232" height="232" rx="52" fill="#B191D8"/>'
    if not flat:
        surface = '<defs><linearGradient id="tile" x1="128" y1="16" x2="128" y2="240" gradientUnits="userSpaceOnUse"><stop stop-color="#C9AFE8"/><stop offset="1" stop-color="#9B79C9"/></linearGradient></defs><rect x="12" y="10" width="232" height="232" rx="52" fill="url(#tile)"/>'
    if not small:
        surface = '<rect x="12" y="16" width="232" height="232" rx="52" fill="#3F285C" opacity=".12"/>' + surface
    transform = 'translate(10.24 4) scale(.92)' if small else 'translate(22 16) scale(.83)'
    shadow = '' if small else f'<path fill="#76529E" opacity=".22" transform="translate(0 6)" d="{CAT}"/>'
    eyes, arrow = (SMALL_EYES, SMALL_ARROW) if small else (EYES, ARROW)
    mascot = f'<g transform="{transform}">{shadow}<path fill="#FFF8F3" d="{CAT}"/><path fill="#62477F" d="{eyes}"/><path fill="#E875AB" d="{arrow}"/></g>'
    return svg('MochiDrop — Mochi courier' + (' — small-size icon' if small else ' — app icon'), surface + mascot)


def write_ico(path, frames):
    # ICO stores an image directory followed by individually rendered PNG frames.
    header = struct.pack('<HHH', 0, 1, len(frames))
    offset = len(header) + 16 * len(frames)
    entries = []
    payloads = []
    for size, payload in frames:
        dimension = size if size < 256 else 0
        entries.append(struct.pack('<BBBBHHII', dimension, dimension, 0, 0, 1, 32, len(payload), offset))
        payloads.append(payload)
        offset += len(payload)
    path.write_bytes(header + b''.join(entries) + b''.join(payloads))


def main():
    for folder in (OUT, OUT / 'png', OUT / 'windows', OUT / 'macos' / 'MochiDrop.iconset', APPICON):
        folder.mkdir(parents=True, exist_ok=True)
    masters = {'icon-master.svg': icon(), 'icon-small.svg': icon(small=True), 'icon-flat.svg': icon(flat=True)}
    for name, content in masters.items():
        (OUT / name).write_text(content, encoding='utf-8', newline='\n')
    for name, color in (('symbol.svg', '#62477F'), ('symbol-black.svg', '#000000'), ('symbol-white.svg', '#FFFFFF')):
        body = f'<path transform="translate(0 -6)" fill="{color}" fill-rule="evenodd" d="{CAT} {EYES} {ARROW}"/>'
        (OUT / name).write_text(svg('MochiDrop — Mochi courier symbol', body), encoding='utf-8', newline='\n')
    small_body = f'<path transform="translate(0 -6)" fill="#62477F" fill-rule="evenodd" d="{CAT} {SMALL_EYES} {SMALL_ARROW}"/>'
    (OUT / 'symbol-small.svg').write_text(svg('MochiDrop — Mochi courier small symbol', small_body), encoding='utf-8', newline='\n')

    frames = []
    for size in SIZES:
        source = masters['icon-small.svg' if size <= 32 else 'icon-master.svg']
        png = cairosvg.svg2png(bytestring=source.encode('utf-8'), output_width=size, output_height=size)
        (OUT / 'png' / f'icon-{size}.png').write_bytes(png)
        if size in ICO_SIZES:
            frames.append((size, png))
    shutil.copyfile(OUT / 'png' / 'icon-1024.png', OUT / 'icon-1024.png')
    write_ico(OUT / 'windows' / 'MochiDrop.ico', frames)

    entries = []
    for points in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            pixels = points * scale
            app_name = f'icon_{pixels}.png'
            shutil.copyfile(OUT / 'png' / f'icon-{pixels}.png', APPICON / app_name)
            iconset_name = f'icon_{points}x{points}' + ('@2x' if scale == 2 else '') + '.png'
            shutil.copyfile(OUT / 'png' / f'icon-{pixels}.png', OUT / 'macos' / 'MochiDrop.iconset' / iconset_name)
            entries.append({'idiom': 'mac', 'size': f'{points}x{points}', 'scale': f'{scale}x', 'filename': app_name})
    (APPICON / 'Contents.json').write_text(json.dumps({'images': entries, 'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n', encoding='utf-8', newline='\n')

    with Image.open(OUT / 'windows' / 'MochiDrop.ico') as image:
        if image.ico.sizes() != {(n, n) for n in ICO_SIZES}:
            raise RuntimeError('ICO is missing an expected frame')
        for size in ICO_SIZES:
            frame = image.ico.getimage((size, size))
            if frame.mode != 'RGBA' or frame.getpixel((0, 0))[3] != 0:
                raise RuntimeError(f'ICO {size}px does not preserve transparent corners')
    for entry in entries:
        expected = int(entry['size'].split('x')[0]) * int(entry['scale'][0])
        with Image.open(APPICON / entry['filename']) as image:
            if image.size != (expected, expected) or image.mode != 'RGBA':
                raise RuntimeError(f'Invalid AppIcon image: {entry["filename"]}')

    kit = ROOT / 'build' / 'MochiDrop-icon-kit.zip'
    kit.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(kit, 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(OUT.rglob('*')):
            if path.is_file():
                archive.write(path, 'MochiDrop-icon-kit/' + path.relative_to(OUT).as_posix())
    print(f'Exported {len(SIZES)} PNG sizes, {len(frames)} ICO frames, and 10 macOS iconset slots.')
    print(f'Validated RGBA transparency and AppIcon dimensions. Kit: {kit}')


if __name__ == '__main__':
    main()
