/// Maps HTTP error codes and exception strings to user-friendly messages.
class ErrorMessages {
  /// Converts an exception string or HTTP status code to a user-friendly
  /// message with actionable guidance.
  static String format(dynamic error) {
    final str = error.toString();

    // Extract HTTP status code if present
    final httpMatch = RegExp(r'HTTP (\d+)').firstMatch(str);
    if (httpMatch != null) {
      final code = int.tryParse(httpMatch.group(1)!) ?? 0;
      return _httpMessage(code, str);
    }

    // Common network errors
    if (str.contains('SocketException') || str.contains('HandshakeException')) {
      return 'Cannot reach the server. Check your network connection '
          'and make sure Hermes is running.';
    }
    if (str.contains('TimeoutException') || str.contains('timeout')) {
      return 'The request timed out. The server may be slow or unreachable. '
          'Try again in a moment.';
    }
    if (str.contains('FormatException') || str.contains('Unexpected end')) {
      return 'Received an invalid response from the server. '
          'The Hermes Gateway may need to be updated.';
    }

    // Fallback: return the raw string, trimmed
    return str.replaceAll('Exception: ', '').trim();
  }

  static String _httpMessage(int code, String raw) {
    switch (code) {
      case 400:
        return 'The request was invalid. This may be a bug in the app — '
            'please report it.';
      case 401:
        return 'Authentication failed. Your API key may be incorrect or '
            'expired. Update it in the connection settings.';
      case 403:
        return 'You do not have permission to perform this action. '
            'Check your account role on the Hermes server.';
      case 404:
        return 'The requested resource was not found. It may have been '
            'deleted or the endpoint is not available on this server.';
      case 409:
        return 'A conflict occurred — the resource may already exist '
            'or be in an incompatible state.';
      case 429:
        return 'Too many requests. The server is rate-limiting you. '
            'Wait a moment and try again.';
      case 500:
        return 'The Hermes server encountered an internal error. '
            'Check the server logs for details.';
      case 502:
      case 503:
        return 'The Hermes server is temporarily unavailable. '
            'It may be restarting — try again in a few seconds.';
      case 504:
        return 'The server did not respond in time. '
            'The network or server may be overloaded.';
      default:
        if (code >= 500) {
          return 'The Hermes server returned an error (HTTP $code). '
              'Check the server logs for details.';
        }
        if (code >= 400) {
          return 'The request could not be completed (HTTP $code).';
        }
        return raw.replaceAll('Exception: ', '').trim();
    }
  }
}
