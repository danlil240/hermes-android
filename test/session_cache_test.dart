import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/session.dart';
import 'package:hermes_android/core/storage/session_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('stores and restores sessions and messages per connection', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final cache = SessionCache(prefs, 'connection-a');
    final session = Session(
      id: 's1',
      title: 'Cached chat',
      model: 'hermes-agent',
      source: 'mobile',
      messageCount: 1,
      isActive: true,
      preview: 'hello',
      startedAt: 123,
    );
    final messages = [
      {'role': 'user', 'content': 'hello'},
      {'role': 'assistant', 'content': 'hi'},
    ];

    await cache.saveSessions([session]);
    await cache.saveMessages('s1', messages);

    final restored = SessionCache(prefs, 'connection-a');
    expect(restored.loadSessions().single.title, 'Cached chat');
    expect(restored.loadMessages('s1'), messages);
  });

  test('does not mix caches between connections', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final first = SessionCache(prefs, 'connection-a');
    final second = SessionCache(prefs, 'connection-b');
    final session = Session(
      id: 's1',
      title: 'Only A',
      model: 'hermes-agent',
      source: 'mobile',
      messageCount: 0,
      isActive: false,
      preview: '',
      startedAt: 123,
    );

    await first.saveSessions([session]);

    expect(second.loadSessions(), isEmpty);
  });

  test('restores generated-title metadata', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final cache = SessionCache(prefs, 'connection-a');
    final session = Session(
      id: 's1',
      title: 'Chat 2026-07-11 12:00',
      model: 'hermes-agent',
      source: 'mobile',
      messageCount: 0,
      isActive: true,
      preview: '',
      startedAt: 123,
      hasGeneratedTitle: true,
    );

    await cache.saveSessions([session]);

    final restored = SessionCache(prefs, 'connection-a').loadSessions().single;
    expect(restored.title, 'Chat 2026-07-11 12:00');
    expect(restored.hasGeneratedTitle, isTrue);
  });
}
