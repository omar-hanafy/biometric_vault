// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility that Flutter provides. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:async';

import 'package:biometric_vault/biometric_vault.dart';
import 'package:biometric_vault_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('biometric_vault');
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  testWidgets('renders example app shell', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Plugin example app'), findsOneWidget);
    expect(find.text('Methods:'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'init'), findsOneWidget);
  });

  testWidgets('handles a canceled delete through the typed error path', (
    WidgetTester tester,
  ) async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      MethodCall call,
    ) async {
      expect(call.method, 'delete');
      throw PlatformException(code: 'AuthError:UserCanceled');
    });
    final controller = TextEditingController();
    final file = BiometricVaultFile(
      MethodChannelBiometricVault(),
      'test_store',
      PromptInfo.defaultValues,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StorageActions(storageFile: file, writeController: controller),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('test_store.delete')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('disposing during capability check stops initialization', (
    WidgetTester tester,
  ) async {
    final response = Completer<String>();
    final calls = <String>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      MethodCall call,
    ) async {
      calls.add(call.method);
      return response.future;
    });
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.widgetWithText(ElevatedButton, 'init'));
    await tester.pump();
    expect(calls, ['canAuthenticate']);
    await tester.pumpWidget(const SizedBox.shrink());
    response.complete('ErrorHwUnavailable');
    await tester.pumpAndSettle();
    expect(calls, ['canAuthenticate']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposes the example input controller with the app', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    final controller = tester
        .widget<TextField>(find.byType(TextField))
        .controller!;
    await tester.pumpWidget(const SizedBox.shrink());
    expect(() => controller.addListener(() {}), throwsFlutterError);
  });
}
