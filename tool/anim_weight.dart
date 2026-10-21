// tool/anim_weight.dart — how many bytes do animations own per model?
// Usage: dart run tool/anim_weight.dart
import 'dart:convert';
import 'dart:io';

const models = [
  'BaseCharacter',
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

int accBytes(Map g, int idx) {
  final acc = (g['accessors'] as List)[idx] as Map;
  final lengths = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16};
  final comp = {'5120': 1, '5121': 1, '5122': 2, '5123': 2, '5125': 4, '5126': 4};
  final n = lengths[acc['type']] ?? 1;
  final s = comp[acc['componentType'].toString()] ?? 1;
  return (acc['count'] as int) * n * s;
}

void main() {
  var totBin = 0, totAnim = 0, totKept = 0;
  const keep = {'Idle', 'Victory', 'Jump', 'RecieveHit', 'Defeat', 'Death'};
  for (final m in models) {
    final g = jsonDecode(
        File('moscot/glTF/$m.gltf').readAsStringSync()) as Map<String, dynamic>;
    final anims = (g['animations'] as List).cast<Map>();
    final animAcc = <int>{};
    final keptAcc = <int>{};
    for (final a in anims) {
      for (final s in (a['samplers'] as List).cast<Map>()) {
        final ia = (s['input'] as int), oa = (s['output'] as int);
        animAcc.add(ia);
        animAcc.add(oa);
        if (keep.contains(a['name'])) {
          keptAcc.add(ia);
          keptAcc.add(oa);
        }
      }
    }
    var animBytes = 0, keptBytes = 0;
    for (final i in animAcc) {
      animBytes += accBytes(g, i);
    }
    for (final i in keptAcc) {
      keptBytes += accBytes(g, i);
    }
    final buffers = (g['buffers'] as List).cast<Map>();
    final bin = (buffers[0]['byteLength'] as int);
    totBin += bin;
    totAnim += animBytes;
    totKept += keptBytes;
    print('$m clips=${anims.length} bin=${(bin / 1024).round()}KB '
        'anim=${(animBytes / 1024).round()}KB kept6=${(keptBytes / 1024).round()}KB');
  }
  print('TOTAL bin=${(totBin / 1024).round()}KB '
      'anim=${(totAnim / 1024).round()}KB kept6=${(totKept / 1024).round()}KB');
}
