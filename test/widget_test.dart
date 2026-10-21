// Minimal checks only (tester is the user on their phone).
import 'package:copy_cat/main.dart';
import 'package:copy_cat/services/audio_scorer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('identical pitch maps score 100', () {
    final pitch = [220.0, 247.0, 262.0, 0.0, 330.0];
    expect(AudioScorer.calculateScore(pitch, List.of(pitch)), 100.0);
  });

  test('judge: identical contour is 100', () {
    final pitch = [220.0, 233.0, 247.0, 262.0, 277.0, 294.0];
    final energy = List<double>.filled(pitch.length, 0.5);
    final verdict = AudioScorer.judge(pitch, pitch,
        targetEnergy: energy, playerEnergy: energy);
    expect(verdict.total, 100.0);
  });

  test('judge: silence is 0', () {
    final tone = [220.0, 233.0, 247.0, 262.0, 277.0, 294.0];
    final silence = List<double>.filled(tone.length, 0.0);
    expect(AudioScorer.judge(tone, silence).total, 0.0);
    expect(AudioScorer.judge(silence, tone).total, 0.0);
  });

  test('judge: transposed melody still scores high', () {
    final pitch = [220.0, 233.0, 247.0, 262.0, 277.0, 294.0];
    final upFifth = pitch.map((f) => f * 1.5).toList();
    final energy = List<double>.filled(pitch.length, 0.5);
    final verdict = AudioScorer.judge(pitch, upFifth,
        targetEnergy: energy, playerEnergy: energy);
    expect(verdict.total, greaterThan(70));
  });

  testWidgets('app launches to Copy Cat splash', (tester) async {
    await tester.pumpWidget(const MimicPartyApp());
    await tester.pump();
    expect(find.text('Copy Cat'), findsOneWidget);
  });
}
