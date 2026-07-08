// Biometric authentication wrapper for app lock functionality.
//
// Uses local_auth to check device capability and prompt the user.
// Falls back gracefully on devices without biometrics — the app lock
// toggle is simply unavailable in that case.
import 'package:local_auth/local_auth.dart';

/// Result of a biometric authentication attempt.
enum BiometricAuthResult {
  success,
  failed,
  unavailable,
  canceled,
}

/// Wraps [LocalAuthentication] to provide a simple interface for
/// biometric app lock.
class BiometricLock {
  final LocalAuthentication _auth;

  BiometricLock([LocalAuthentication? auth])
      : _auth = auth ?? LocalAuthentication();

  /// Returns true if the device has biometric hardware and at least one
  /// enrolled fingerprint/face/iris.
  Future<bool> isAvailable() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isDeviceSupported = await _auth.isDeviceSupported();
      return canCheck && isDeviceSupported;
    } catch (_) {
      return false;
    }
  }

  /// Attempts biometric authentication. Returns a [BiometricAuthResult]
  /// indicating the outcome.
  Future<BiometricAuthResult> authenticate({
    String reason = 'Please authenticate to unlock Hermes',
  }) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
      return ok
          ? BiometricAuthResult.success
          : BiometricAuthResult.failed;
    } on Exception catch (_) {
      // User canceled or biometric not available
      return BiometricAuthResult.canceled;
    }
  }
}
