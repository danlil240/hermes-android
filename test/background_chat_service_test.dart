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

  test('hands a complete streaming request to the Android foreground service',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'startChat');
      expect(call.arguments, {
        'endpoint': 'https://hermes.example.com/v1/chat/completions',
        'headers': {
          'Authorization': 'Bearer key',
          'X-Hermes-Session-Id': 'session-123',
        },
        'body': '{"stream":true}',
        'sessionId': 'session-123',
      });
      return true;
    });

    final started = await BackgroundChatService.start(
      endpoint: 'https://hermes.example.com/v1/chat/completions',
      headers: const {
        'Authorization': 'Bearer key',
        'X-Hermes-Session-Id': 'session-123',
      },
      body: '{"stream":true}',
      sessionId: 'session-123',
    );

    expect(started, isTrue);
  });
}
