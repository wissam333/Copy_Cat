// tool/split_sprite.dart — cuts the myinstants two-frame sprite into two
// exact PNGs (left half = normal, right half = pressed). No runtime
// alignment tricks, so the wrong frame can never show.
import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  final src = img.decodePng(
      File('assets/transparent_button_small_sprite.png')
          .readAsBytesSync())!;
  final half = src.width ~/ 2;
  final left = img.copyCrop(src, x: 0, y: 0, width: half, height: src.height);
  final right = img.copyCrop(src,
      x: half, y: 0, width: src.width - half, height: src.height);
  File('assets/sprite_play_normal.png')
      .writeAsBytesSync(img.encodePng(left));
  File('assets/sprite_play_pressed.png')
      .writeAsBytesSync(img.encodePng(right));
  print('normal ${left.width}x${left.height}, '
      'pressed ${right.width}x${right.height}');
}
