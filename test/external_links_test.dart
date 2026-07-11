import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/shared/external_links.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode;

void main() {
  test('opens HTTPS links in the external browser', () async {
    Uri? openedUri;
    LaunchMode? openedMode;

    final opened = await openExternalLink(
      'https://github.com/danlil240/hermes-android/releases/tag/v1.0.11',
      launcher: (uri, mode) async {
        openedUri = uri;
        openedMode = mode;
        return true;
      },
    );

    expect(opened, isTrue);
    expect(openedUri, Uri.parse('https://github.com/danlil240/hermes-android/releases/tag/v1.0.11'));
    expect(openedMode, LaunchMode.externalApplication);
  });

  test('rejects non-web links', () async {
    var launcherCalled = false;

    final opened = await openExternalLink(
      'mailto:daniel@example.com',
      launcher: (_, _) async {
        launcherCalled = true;
        return true;
      },
    );

    expect(opened, isFalse);
    expect(launcherCalled, isFalse);
  });
}
