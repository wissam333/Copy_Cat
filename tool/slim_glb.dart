// tool/slim_glb.dart — keeps only the celebration clips in each model.
// Drops 11 of 17 animations (7.3MB -> 3.8MB binary) and rebuilds the .glb.
//
// Usage: dart run tool/slim_glb.dart
// Reads moscot/glTF/<name>.gltf, writes assets/mascot3d/<name>.glb.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const models = [
  'Casual_Male',
  'Casual_Female',
  'Ninja_Male',
  'Pirate_Male',
  'Viking_Male',
  'Wizard',
  'Witch',
  'Zombie_Male',
  'Goblin_Male',
  'Elf',
  'Chef_Male',
  'Cow',
  'Pug',
];

const keepClips = {'Idle', 'Victory', 'Jump', 'RecieveHit', 'Defeat', 'Death'};

void main() {
  Directory('assets/mascot3d').createSync(recursive: true);
  for (final m in models) {
    final before = File('assets/mascot3d/$m.glb').lengthSync();
    final glb = slim('moscot/glTF/$m.gltf');
    File('assets/mascot3d/$m.glb').writeAsBytesSync(glb);
    final after = File('assets/mascot3d/$m.glb').lengthSync();
    print('$m ${(before / 1024).round()}KB -> ${(after / 1024).round()}KB');
  }
}

Uint8List slim(String src) {
  final g = jsonDecode(File(src).readAsStringSync()) as Map<String, dynamic>;
  final accessors = (g['accessors'] as List).cast<Map>();
  final views = (g['bufferViews'] as List).cast<Map>();

  // 1. Drop animations outside the keep set.
  final anims = (g['animations'] as List).cast<Map>();
  final keptAnims = [for (final a in anims) if (keepClips.contains(a['name'])) a];
  if (keptAnims.length != keepClips.length) {
    final names = {for (final a in keptAnims) a['name']};
    print('WARNING $src missing: ${keepClips.difference(names)}');
  }
  g['animations'] = keptAnims;

  // 2. Collect used accessor indices (animations + meshes + skins).
  final used = <int>{};
  for (final a in keptAnims) {
    for (final s in (a['samplers'] as List).cast<Map>()) {
      used.add(s['input'] as int);
      used.add(s['output'] as int);
    }
  }
  for (final mesh in (g['meshes'] as List).cast<Map>()) {
    for (final p in (mesh['primitives'] as List).cast<Map>()) {
      for (final v in (p['attributes'] as Map).values) {
        used.add(v as int);
      }
      if (p['indices'] != null) used.add(p['indices'] as int);
    }
  }
  for (final skin in (g['skins'] as List).cast<Map>()) {
    if (skin['inverseBindMatrices'] != null) {
      used.add(skin['inverseBindMatrices'] as int);
    }
  }

  // 3. Compact buffer: keep used views, concatenate their bytes.
  const prefix = 'data:application/octet-stream;base64,';
  final uri = ((g['buffers'] as List)[0] as Map)['uri'] as String;
  final bin = base64Decode(uri.substring(prefix.length));
  final viewBytes = <int, Uint8List>{};
  for (var i = 0; i < views.length; i++) {
    final v = views[i];
    final off = (v['byteOffset'] as int?) ?? 0;
    final len = v['byteLength'] as int;
    // Referenced at all? (views can back several accessors)
    var needed = false;
    for (var a = 0; a < accessors.length; a++) {
      if (used.contains(a) && accessors[a]['bufferView'] == i) {
        needed = true;
        break;
      }
    }
    if (needed) viewBytes[i] = bin.sublist(off, off + len);
  }
  final newViews = <Map>[];
  final viewMap = <int, int>{};
  final out = BytesBuilder();
  var cursor = 0;
  for (var i = 0; i < views.length; i++) {
    final bytes = viewBytes[i];
    if (bytes == null) continue;
    viewMap[i] = newViews.length;
    final v = Map<String, dynamic>.from(views[i]);
    v['byteOffset'] = cursor;
    v['byteLength'] = bytes.length;
    newViews.add(v);
    out.add(bytes);
    cursor += bytes.length;
  }
  g['bufferViews'] = newViews;

  // 4. Compact accessors, remap every reference.
  final newAcc = <Map>[];
  final accMap = <int, int>{};
  for (var i = 0; i < accessors.length; i++) {
    if (!used.contains(i)) continue;
    accMap[i] = newAcc.length;
    final a = Map<String, dynamic>.from(accessors[i]);
    if (a['bufferView'] != null) a['bufferView'] = viewMap[a['bufferView']];
    newAcc.add(a);
  }
  g['accessors'] = newAcc;
  for (final a in keptAnims) {
    for (final s in (a['samplers'] as List).cast<Map>()) {
      s['input'] = accMap[s['input']];
      s['output'] = accMap[s['output']];
    }
  }
  for (final mesh in (g['meshes'] as List).cast<Map>()) {
    for (final p in (mesh['primitives'] as List).cast<Map>()) {
      final attrs = Map<String, dynamic>.from(p['attributes'] as Map);
      for (final k in attrs.keys) {
        attrs[k] = accMap[attrs[k]];
      }
      p['attributes'] = attrs;
      if (p['indices'] != null) p['indices'] = accMap[p['indices']];
    }
  }
  for (final skin in (g['skins'] as List).cast<Map>()) {
    if (skin['inverseBindMatrices'] != null) {
      skin['inverseBindMatrices'] = accMap[skin['inverseBindMatrices']];
    }
  }

  // 5. New buffer + pack GLB.
  final binBytes = out.toBytes();
  (g['buffers'] as List)[0] = {'byteLength': binBytes.length};
  return _packGlb(utf8.encode(jsonEncode(g)), binBytes);
}

Uint8List _packGlb(List<int> json, Uint8List bin) {
  Uint8List pad(List<int> d, int b) {
    if (d.length % 4 == 0) return Uint8List.fromList(d);
    final o = Uint8List(d.length + (4 - d.length % 4));
    o.setRange(0, d.length, d);
    for (var i = d.length; i < o.length; i++) {
      o[i] = b;
    }
    return o;
  }

  final j = pad(json, 0x20);
  final b = pad(bin, 0);
  final total = 12 + 8 + j.length + 8 + b.length;
  final out = BytesBuilder();
  out.add(_u32(0x46546C67));
  out.add(_u32(2));
  out.add(_u32(total));
  out.add(_u32(j.length));
  out.add(_u32(0x4E4F534A));
  out.add(j);
  out.add(_u32(b.length));
  out.add(_u32(0x004E4942));
  out.add(b);
  return out.toBytes();
}

Uint8List _u32(int v) {
  final b = ByteData(4)..setUint32(0, v, Endian.little);
  return b.buffer.asUint8List();
}
