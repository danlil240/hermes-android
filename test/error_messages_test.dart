import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/shared/errors/error_messages.dart';

void main() {
  group('ErrorMessages.format', () {
    test('maps 401 to authentication message', () {
      final msg = ErrorMessages.format(Exception('HTTP 401: Unauthorized'));
      expect(msg, contains('Authentication failed'));
      expect(msg, contains('API key'));
    });

    test('maps 404 to not found message', () {
      final msg = ErrorMessages.format(Exception('HTTP 404: Not Found'));
      expect(msg, contains('not found'));
    });

    test('maps 429 to rate limit message', () {
      final msg = ErrorMessages.format(Exception('HTTP 429'));
      expect(msg, contains('rate-limiting'));
    });

    test('maps 500 to internal error message', () {
      final msg = ErrorMessages.format(Exception('HTTP 500: Internal'));
      expect(msg, contains('internal error'));
    });

    test('maps 503 to unavailable message', () {
      final msg = ErrorMessages.format(Exception('HTTP 503'));
      expect(msg, contains('temporarily unavailable'));
    });

    test('maps socket exception to network message', () {
      final msg = ErrorMessages.format(
        Exception('SocketException: Connection refused'),
      );
      expect(msg, contains('Cannot reach the server'));
    });

    test('maps timeout exception to timeout message', () {
      final msg = ErrorMessages.format(
        Exception('TimeoutException after 0:00:05'),
      );
      expect(msg, contains('timed out'));
    });

    test('strips Exception: prefix from fallback', () {
      final msg = ErrorMessages.format(Exception('Something weird happened'));
      expect(msg, 'Something weird happened');
    });

    test('handles unknown HTTP codes gracefully', () {
      final msg = ErrorMessages.format(Exception('HTTP 418'));
      expect(msg, contains('HTTP 418'));
    });
  });
}
