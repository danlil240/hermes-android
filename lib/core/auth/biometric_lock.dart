// Biometric authentication wrapper for app lock functionality.
//
// Uses local_auth to check device capability and prompt the user.
// Falls back gracefully on devices without biometrics — the app lock
// toggle is simply unavailable in that case.
import 'package:flutter/services.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:local_auth/local_auth.dart';

/// Result of a biometric authentication attempt.
enum BiometricAuthResult { success, failed, unavailable, canceled }

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
      final enrolledBiometrics = await _auth.getAvailableBiometrics();
      return canCheck && isDeviceSupported && enrolledBiometrics.isNotEmpty;
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
      return ok ? BiometricAuthResult.success : BiometricAuthResult.failed;
    } on PlatformException catch (e) {
      switch (e.code) {
        case auth_error.notAvailable:
        case auth_error.notEnrolled:
        case auth_error.passcodeNotSet:
        case auth_error.otherOperatingSystem:
        case 'no_activity':
        case 'no_fragment_activity':
          return BiometricAuthResult.unavailable;
        case auth_error.lockedOut:
        case auth_error.permanentlyLockedOut:
          return BiometricAuthResult.failed;
        default:
          return BiometricAuthResult.canceled;
      }
    } on Exception catch (_) {
      return BiometricAuthResult.canceled;
    }
  }
}
