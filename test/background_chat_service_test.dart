import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/network/background_chat_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('hermes/background_chat');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('submits a server-owned run for background synchronization',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'startChat');
      expect(call.arguments, {
        'endpoint': 'https://hermes.example.com/v1/runs',
        'headers': {
          'Authorization': 'Bearer key',
          'X-Hermes-Session-Id': 'session-123',
        },
        'body': '{"input":"hello","session_id":"session-123"}',
        'sessionId': 'session-123',
      });
      return true;
    });

    final started = await BackgroundChatService.start(
      endpoint: 'https://hermes.example.com/v1/runs',
      headers: const {
        'Authorization': 'Bearer key',
        'X-Hermes-Session-Id': 'session-123',
      },
      body: '{"input":"hello","session_id":"session-123"}',
      sessionId: 'session-123',
    );

    expect(started, isTrue);
  });
}
