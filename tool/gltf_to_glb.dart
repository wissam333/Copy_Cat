// tool/gltf_to_glb.dart — repacks single-file embedded .gltf to .glb.
// The moscot glTFs are one .gltf file with a single data: base64 buffer.
// flutter_scene's build hook only converts .glb, so we convert here.
//
// Usage: dart run tool/gltf_to_glb.dart Pirate_Male Chef_Hat
// Writes assets/mascot3d/<Name>.glb
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

void main(List<String> args) {
  if (args.isEmpty) {
    print('usage: dart run tool/gltf_to_glb.dart <BaseName> [...]');
    exit(1);
  }
  Directory('assets/mascot3d').createSync(recursive: true);
  for (final name in args) {
    final src = 'moscot/glTF/$name.gltf';
    final dst = 'assets/mascot3d/$name.glb';
    final jsonText = File(src).readAsStringSync();
    final gltf = jsonDecode(jsonText) as Map<String, dynamic>;
    final buffers = gltf['buffers'] as List;
    if (buffers.length != 1) {
      print('$name: expected 1 embedded buffer, found ${buffers.length} — skip');
      continue;
    }
    final uri = (buffers[0] as Map)['uri'] as String;
    const prefix = 'data:application/octet-stream;base64,';
    if (!uri.startsWith(prefix)) {
      print('$name: buffer is not an embedded octet-stream — skip');
      continue;
    }
    final bin = base64Decode(uri.substring(prefix.length));
    (buffers[0] as Map).remove('uri');
    // Drop empty byteLength? flutter_scene importer needs correct byteLength.
    (buffers[0] as Map)['byteLength'] = bin.length;
    final jsonBytes = utf8.encode(jsonEncode(gltf));
    final jsonPadded = _pad(jsonBytes, 0x20); // space
    final binPadded = _pad(bin, 0);
    final totalLen = 12 + 8 + jsonPadded.length + 8 + binPadded.length;
    final out = BytesBuilder();
    out.add(_u32(0x46546C67)); // 'glTF'
    out.add(_u32(2));
    out.add(_u32(totalLen));
    out.add(_u32(jsonPadded.length));
    out.add(_u32(0x4E4F534A)); // 'JSON'
    out.add(jsonPadded);
    out.add(_u32(binPadded.length));
    out.add(_u32(0x004E4942)); // 'BIN\0'
    out.add(binPadded);
    File(dst).writeAsBytesSync(out.toBytes());
    print('$name -> $dst (${(File(dst).lengthSync() / 1024).round()} KB)');
  }
}

Uint8List _pad(List<int> data, int padByte) {
  final rem = data.length % 4;
  if (rem == 0) return Uint8List.fromList(data);
  final out = Uint8List(data.length + (4 - rem));
  out.setRange(0, data.length, data);
  for (var i = data.length; i < out.length; i++) {
    out[i] = padByte;
  }
  return out;
}

Uint8List _u32(int v) {
  final b = ByteData(4)..setUint32(0, v, Endian.little);
  return b.buffer.asUint8List();
}
