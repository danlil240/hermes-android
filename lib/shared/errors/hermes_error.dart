import '../../core/models/connection.dart';

/// Which API surface the error originated from.
enum HermesErrorSource { api, dashboard }

/// Classified error type for actionable recovery.
enum HermesErrorType {
  networkUnavailable,
  serverRestarting,
  authFailure,
  dashboardAuthRequired,
  cloudflareAccessRequired,
  unsupportedEndpoint,
  permissionDenied,
  transientServerError,
  unknown,
}

/// A classified error with a user-friendly message and known recovery path.
class HermesError {
  final HermesErrorType type;
  final String message;
  final dynamic rawError;

  const HermesError({
    required this.type,
    required this.message,
    this.rawError,
  });

  /// Classifies a raw exception into a [HermesError] with an actionable
  /// message. Pass [source] to distinguish API-key failures from dashboard
  /// auth failures. Pass [connection] to detect unconfigured dashboard creds.
  static HermesError classify(
    dynamic error, {
    HermesErrorSource source = HermesErrorSource.api,
    SavedConnection? connection,
  }) {
    final str = error.toString();

    // Pre-check: dashboard not configured at all
    if (connection != null &&
        source == HermesErrorSource.dashboard &&
        !connection.isDashboardConfigured) {
      return HermesError(
        type: HermesErrorType.dashboardAuthRequired,
        message: 'Dashboard credentials are not configured for this connection. '
            'Set up dashboard authentication to use this feature.',
        rawError: error,
      );
    }

    // Extract HTTP status code if present
    final httpMatch = RegExp(r'HTTP (\d+)').firstMatch(str);
    if (httpMatch != null) {
      final code = int.tryParse(httpMatch.group(1)!) ?? 0;
      return _classifyHttp(code, str, source);
    }

    // Dashboard-specific error strings
    if (str.contains('Dashboard login failed')) {
      return HermesError(
        type: HermesErrorType.dashboardAuthRequired,
        message: source == HermesErrorSource.dashboard
            ? 'Dashboard login failed. The username or password may be '
                'incorrect or expired.'
            : 'Authentication failed. Your credentials may be incorrect or '
                'expired.',
        rawError: error,
      );
    }
    if (str.contains('Dashboard not reachable')) {
      return HermesError(
        type: HermesErrorType.networkUnavailable,
        message: 'Cannot reach the dashboard. Check your network connection '
            'and make sure the Hermes dashboard is running.',
        rawError: error,
      );
    }
    if (str.contains('Session token not found') ||
        str.contains('no session cookie found')) {
      return HermesError(
        type: HermesErrorType.dashboardAuthRequired,
        message: 'Could not authenticate with the dashboard. Dashboard '
            'credentials may be required.',
        rawError: error,
      );
    }

    // Network errors
    if (str.contains('SocketException') || str.contains('HandshakeException')) {
      return HermesError(
        type: HermesErrorType.networkUnavailable,
        message: 'Cannot reach the server. Check your network connection '
            'and make sure Hermes is running.',
        rawError: error,
      );
    }
    if (str.contains('TimeoutException') || str.contains('timeout')) {
      return HermesError(
        type: HermesErrorType.transientServerError,
        message: 'The request timed out. The server may be slow or '
            'unreachable. Try again in a moment.',
        rawError: error,
      );
    }
    if (str.contains('FormatException') || str.contains('Unexpected end')) {
      return HermesError(
        type: HermesErrorType.unsupportedEndpoint,
        message: 'Received an invalid response from the server. '
            'The Hermes Gateway may need to be updated.',
        rawError: error,
      );
    }

    // Fallback
    return HermesError(
      type: HermesErrorType.unknown,
      message: str.replaceAll('Exception: ', '').trim(),
      rawError: error,
    );
  }

  static HermesError _classifyHttp(
    int code,
    String raw,
    HermesErrorSource source,
  ) {
    switch (code) {
      case 400:
        return HermesError(
          type: HermesErrorType.unknown,
          message: 'The request was invalid. This may be a bug in the app — '
              'please report it.',
          rawError: raw,
        );
      case 401:
        if (source == HermesErrorSource.dashboard) {
          return HermesError(
            type: HermesErrorType.dashboardAuthRequired,
            message: 'Dashboard authentication failed. The username or '
                'password may be incorrect or expired.',
            rawError: raw,
          );
        }
        return HermesError(
          type: HermesErrorType.authFailure,
          message: 'Authentication failed. Your API key may be incorrect or '
              'expired. Update it in the connection settings.',
          rawError: raw,
        );
      case 403:
        if (raw.toLowerCase().contains('cloudflare') ||
            raw.contains('CF-Access') ||
            raw.contains('cf-access')) {
          return HermesError(
            type: HermesErrorType.cloudflareAccessRequired,
            message: 'Cloudflare Access is blocking this request. Make sure '
                'the Cloudflare Access service token is configured correctly '
                'in the connection settings.',
            rawError: raw,
          );
        }
        return HermesError(
          type: HermesErrorType.permissionDenied,
          message: 'You do not have permission to perform this action. '
              'Check your account role on the Hermes server.',
          rawError: raw,
        );
      case 404:
        return HermesError(
          type: HermesErrorType.unsupportedEndpoint,
          message: 'The requested endpoint was not found. This feature may '
              'not be available on your server version.',
          rawError: raw,
        );
      case 409:
        return HermesError(
          type: HermesErrorType.unknown,
          message: 'A conflict occurred — the resource may already exist '
              'or be in an incompatible state.',
          rawError: raw,
        );
      case 429:
        return HermesError(
          type: HermesErrorType.transientServerError,
          message: 'Too many requests. The server is rate-limiting you. '
              'Wait a moment and try again.',
          rawError: raw,
        );
      case 500:
        return HermesError(
          type: HermesErrorType.transientServerError,
          message: 'The Hermes server encountered an internal error. '
              'Check the server logs for details.',
          rawError: raw,
        );
      case 502:
      case 503:
        return HermesError(
          type: HermesErrorType.serverRestarting,
          message: 'The Hermes server is temporarily unavailable. '
              'It may be restarting — try again in a few seconds.',
          rawError: raw,
        );
      case 504:
        return HermesError(
          type: HermesErrorType.transientServerError,
          message: 'The server did not respond in time. '
              'The network or server may be overloaded.',
          rawError: raw,
        );
      default:
        if (code >= 500) {
          return HermesError(
            type: HermesErrorType.transientServerError,
            message: 'The Hermes server returned an error (HTTP $code). '
                'Check the server logs for details.',
            rawError: raw,
          );
        }
        if (code >= 400) {
          return HermesError(
            type: HermesErrorType.unknown,
            message: 'The request could not be completed (HTTP $code).',
            rawError: raw,
          );
        }
        return HermesError(
          type: HermesErrorType.unknown,
          message: raw.replaceAll('Exception: ', '').trim(),
          rawError: raw,
        );
    }
  }

  bool get isTransient =>
      type == HermesErrorType.serverRestarting ||
      type == HermesErrorType.transientServerError;

  bool get isAuthError =>
      type == HermesErrorType.authFailure ||
      type == HermesErrorType.dashboardAuthRequired ||
      type == HermesErrorType.cloudflareAccessRequired;
}
