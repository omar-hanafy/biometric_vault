import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The single method channel used by the plugin on Android, iOS, macOS and
/// Linux.
const channel = MethodChannel('biometric_vault');

/// Installs a mock handler on [channel], records every incoming call and
/// answers with whatever [handler] returns (or throws).
class ChannelHarness {
  ChannelHarness() {
    TestWidgetsFlutterBinding.ensureInitialized();
  }

  final List<MethodCall> calls = [];

  /// Answers a method call. Throw a [PlatformException] to simulate a native
  /// error; return a value to simulate a native result.
  Object? Function(MethodCall call)? handler;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          return handler?.call(call);
        });
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  }

  MethodCall get single {
    expect(calls, hasLength(1));
    return calls.single;
  }

  Map<Object?, Object?> argumentsOf(MethodCall call) =>
      call.arguments as Map<Object?, Object?>;
}
