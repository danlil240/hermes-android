import 'hermes_error.dart';

/// Maps HTTP error codes and exception strings to user-friendly messages.
///
/// Delegates to [HermesError.classify] so there is a single source of truth
/// for error classification. Use [HermesErrorState] for full-screen error
/// recovery UI; use [ErrorMessages.format] for lightweight snackbar messages.
class ErrorMessages {
  /// Converts an exception to a user-friendly message with actionable
  /// guidance.
  static String format(dynamic error) {
    return HermesError.classify(error).message;
  }
}
