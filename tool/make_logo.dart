// tool/make_logo.dart — draws the Copy Cat paw logo (no image files needed).
// Outputs:
//   assets/logo/cat_paw.png ......... transparent, for in-app use
//   android mipmap-*/ic_launcher.png  purple-backed launcher icons
//
// Usage: dart run tool/make_logo.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const _primary = (103, 80, 164); // Colors.deepPurple / scheme.primary
const _white = (255, 255, 255);

void _disc(img.Image im, int cx, int cy, int r, (int, int, int) c) {
  img.fillCircle(im,
      x: cx,
      y: cy,
      radius: r,
      color: img.ColorRgb8(c.$1, c.$2, c.$3));
}

void _ellipse(img.Image im, int cx, int cy, int rx, int ry,
    (int, int, int) c) {
  final pts = <img.Point>[];
  for (var i = 0; i < 72; i++) {
    final a = i / 72 * math.pi * 2;
    pts.add(img.Point(
        (cx + rx * math.cos(a)).toInt(),
        (cy + ry * math.sin(a)).toInt()));
  }
  img.fillPolygon(im,
      vertices: pts, color: img.ColorRgb8(c.$1, c.$2, c.$3));
}

void _paw(img.Image im, double s, {double ox = 0, double oy = 0}) {
  int v(double x, double o) => (x * s + o).toInt();
  // Flat splash-style paw: solid primary toes + pad, no outlines.
  const toes = [
    (140.0, 195.0, 44.0),
    (218.0, 152.0, 46.0),
    (296.0, 152.0, 46.0),
    (374.0, 197.0, 44.0),
  ];
  for (final (tx, ty, tr) in toes) {
    _disc(im, v(tx, ox), v(ty, oy), v(tr, 0), _primary);
  }
  _ellipse(im, v(256, ox), v(335, oy), v(112, 0), v(90, 0), _primary);
}

void main() {
  const base = 512;
  Directory('assets/logo').createSync(recursive: true);

  // 1. Transparent in-app logo.
  final logo = img.Image(width: base, height: base, numChannels: 4);
  img.fill(logo, color: img.ColorRgba8(0, 0, 0, 0));
  _paw(logo, 1.0);
  File('assets/logo/cat_paw.png')
      .writeAsBytesSync(img.encodePng(logo));
  print('assets/logo/cat_paw.png');

  // 2. Launcher icons: primary tile + white badge circle + paw,
  // a mini version of the splash badge.
  final tile = img.Image(width: base, height: base, numChannels: 4);
  img.fill(tile,
      color: img.ColorRgb8(_primary.$1, _primary.$2, _primary.$3));
  _disc(tile, base ~/ 2, base ~/ 2, 190, _white);
  const ps = 0.72;
  _paw(tile, ps,
      ox: base * (1 - ps) / 2, oy: base * (1 - ps) / 2 - 14);
  const sizes = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
  };
  for (final e in sizes.entries) {
    final small = img.copyResize(tile, width: e.value, height: e.value);
    final path =
        'android/app/src/main/res/${e.key}/ic_launcher.png';
    File(path).writeAsBytesSync(img.encodePng(small));
    print('$path (${e.value})');
  }
}
