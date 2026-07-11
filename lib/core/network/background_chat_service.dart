import 'dart:async';

import 'package:flutter/services.dart';

/// An event emitted by Android's foreground chat service.
///
/// The service, rather than the screen widget, owns the long-running HTTP
/// request. This lets Hermes finish a turn after the user backgrounds or
/// swipes away the app activity.
class BackgroundChatEvent {
  final String sessionId;
  final String type;
  final String? token;
  final String? error;

  const BackgroundChatEvent({
    required this.sessionId,
    required this.type,
    this.token,
    this.error,
  });

  factory BackgroundChatEvent.fromMap(Map<Object?, Object?> map) {
    return BackgroundChatEvent(
      sessionId: map['sessionId']?.toString() ?? '',
      type: map['type']?.toString() ?? '',
      token: map['token']?.toString(),
      error: map['error']?.toString(),
    );
  }
}

/// Bridge to Android's status-sync service for server-owned Hermes runs.
///
/// Calls gracefully return `false` on platforms that do not implement the
/// bridge, allowing the normal Dart SSE client to remain the fallback.
class BackgroundChatService {
  static const _methods = MethodChannel('hermes/background_chat');
  static const _events = EventChannel('hermes/background_chat/events');

  static final Stream<BackgroundChatEvent> events = _events
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map(
        (event) => BackgroundChatEvent.fromMap(
          Map<Object?, Object?>.from(event as Map),
        ),
      )
      .asBroadcastStream();

  static Future<bool> start({
    required String endpoint,
    required Map<String, String> headers,
    required String body,
    required String sessionId,
  }) async {
    try {
      return await _methods.invokeMethod<bool>('startChat', {
            'endpoint': endpoint,
            'headers': headers,
            'body': body,
            'sessionId': sessionId,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
