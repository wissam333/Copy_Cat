import "dart:io";
import "package:image/image.dart" as img;
void main() {
  final im = img.decodePng(File("assets/transparent_button_small_sprite.png").readAsBytesSync())!;
  print("sprite ${im.width}x${im.height} channels=${im.numChannels}");
  final sh = File("assets/transparent_button_small_shadow.webp").readAsBytesSync();
  final im2 = img.decodeWebP(sh);
  print("shadow ${im2 == null ? "unreadable" : "${im2.width}x${im2.height}"}");
}

void split() {}
