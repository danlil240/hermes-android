import 'package:url_launcher/url_launcher.dart';

typedef ExternalLinkLauncher = Future<bool> Function(Uri uri, LaunchMode mode);

/// Opens an HTTP(S) link outside Hermes Android.
///
/// Markdown can contain arbitrary URI schemes; only web links are accepted so
/// a chat message cannot invoke device-specific actions such as `tel:` or
/// `intent:` links.
Future<bool> openExternalLink(
  String href, {
  ExternalLinkLauncher? launcher,
}) async {
  final uri = Uri.tryParse(href);
  if (uri == null ||
      uri.host.isEmpty ||
      (uri.scheme != 'http' && uri.scheme != 'https')) {
    return false;
  }

  final open = launcher ?? _launchExternalApplication;
  return open(uri, LaunchMode.externalApplication);
}

Future<bool> _launchExternalApplication(Uri uri, LaunchMode mode) {
  return launchUrl(uri, mode: mode);
}
