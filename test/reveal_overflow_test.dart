// Catches RenderFlex overflow on the solo reveal (score) screen.
// The tester saw yellow/black stripes there; any overflow throws here.
import 'package:copy_cat/screens/gameplay_screen.dart';
import 'package:copy_cat/services/audio_io_service.dart';
import 'package:copy_cat/state/game_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeIo extends AudioIoService {
  @override
  Future<bool> ensureMicPermission() async => true;
  @override
  Future<String?> recordWav(String path, Duration recordFor) async => path;
  @override
  Future<void> cancelRecording() async {}
  @override
  Future<void> playOnce(String path) async {}
  @override
  Future<void> stopPlayback() async {}
  @override
  Future<String?> decodeToWav(String path) async => path;
  @override
  Future<Duration?> probeDuration(String path) async => Duration.zero;
}

Future<void> _pumpReveal(WidgetTester tester,
    {required double score,
    required double melody,
    required double rhythm,
    required bool pitched}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [audioIoProvider.overrideWithValue(_FakeIo())],
      child: const MaterialApp(home: GameplayScreen(solo: true)),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  final container =
      ProviderScope.containerOf(tester.element(find.byType(GameplayScreen)));
  final ctl = container.read(gameProvider.notifier);
  ctl.addPlayer('س');
  final serial = ctl.openSubmission();
  ctl.completeTurn(
    serial: serial,
    score: score,
    melody: melody,
    rhythm: rhythm,
    pitched: pitched,
  );
  await tester.pump();
  // Let the dramatic spin land (~1.5 s) plus spring settle.
  await tester.pump(const Duration(seconds: 2));
  await tester.pump(const Duration(milliseconds: 800));
}

void main() {
  testWidgets('reveal fits a 360x640 phone, pitched score', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpReveal(tester,
        score: 85, melody: 80, rhythm: 75, pitched: true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reveal fits a 360x640 phone, silent take', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpReveal(tester,
        score: 0, melody: 0, rhythm: 0, pitched: false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reveal fits a tiny 320x568 phone', (tester) async {
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpReveal(tester,
        score: 72, melody: 70, rhythm: 74, pitched: true);
    expect(tester.takeException(), isNull);
  });
}
