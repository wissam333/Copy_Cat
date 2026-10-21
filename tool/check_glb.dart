// tool/check_glb.dart — lists animations + counts in a packed .glb.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

void main(List<String> args) {
  for (final p in args) {
    final b = File(p).readAsBytesSync();
    final bd = ByteData.sublistView(b);
    final jsonLen = bd.getUint32(12, Endian.little);
    final g = jsonDecode(utf8.decode(b.sublist(20, 20 + jsonLen))) as Map;
    final anims = (g['animations'] as List).cast<Map>();
    print('$p anims=${anims.map((a) => a['name']).toList()} '
        'acc=${(g['accessors'] as List).length} '
        'views=${(g['bufferViews'] as List).length} '
        'bin=${(g['buffers'] as List)[0]['byteLength']}');
  }
}
