/// Session model matching the Gateway API Server response format.
class Session {
  static const int _maxTitleLength = 60;

  final String id;
  final String title;
  final String model;
  final String source;
  final int messageCount;
  final bool isActive;
  final String preview;
  final double startedAt;
  final double? endedAt;
  final bool hasGeneratedTitle;

  const Session({
    required this.id,
    required this.title,
    required this.model,
    required this.source,
    required this.messageCount,
    required this.isActive,
    required this.preview,
    required this.startedAt,
    this.endedAt,
    this.hasGeneratedTitle = false,
  });

  static bool isPlaceholderTitle(String title) {
    final normalized = _collapseWhitespace(title).toLowerCase();
    return normalized.isEmpty ||
        normalized == 'untitled' ||
        normalized == 'untitled session' ||
        normalized == 'new chat';
  }

  static bool isAutoTitleCandidate(Session session, String title) {
    final normalized = _collapseWhitespace(title);
    if (session.hasGeneratedTitle) return true;
    if (isPlaceholderTitle(normalized)) return true;
    return normalized ==
        displayTitle(
          title: '',
          preview: session.preview,
          startedAt: session.startedAt,
          id: session.id,
        );
  }

  static String displayTitle({
    String? title,
    String? preview,
    double? startedAt,
    String? id,
  }) {
    final cleanedTitle = _collapseWhitespace(title ?? '');
    if (!isPlaceholderTitle(cleanedTitle)) {
      return _truncateTitle(cleanedTitle);
    }

    final previewTitle = _titleFromPreview(preview);
    if (previewTitle.isNotEmpty) return previewTitle;

    final datedTitle = _titleFromStartedAt(startedAt);
    if (datedTitle.isNotEmpty) return datedTitle;

    final shortId = _shortId(id);
    if (shortId.isNotEmpty) return 'Session $shortId';

    return 'New Chat';
  }

  Session copyWith({
    String? id,
    String? title,
    String? model,
    String? source,
    int? messageCount,
    bool? isActive,
    String? preview,
    double? startedAt,
    double? endedAt,
    bool? hasGeneratedTitle,
  }) {
    return Session(
      id: id ?? this.id,
      title: title ?? this.title,
      model: model ?? this.model,
      source: source ?? this.source,
      messageCount: messageCount ?? this.messageCount,
      isActive: isActive ?? this.isActive,
      preview: preview ?? this.preview,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      hasGeneratedTitle:
          hasGeneratedTitle ?? (title != null ? false : this.hasGeneratedTitle),
    );
  }

  factory Session.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    final rawTitle = json['title']?.toString();
    final preview = json['preview']?.toString() ?? '';
    final startedAt = _toDouble(json['started_at']);
    final endedAtRaw = json['ended_at'];
    final endedAt = endedAtRaw == null ? null : _toDouble(endedAtRaw);
    final hasGeneratedTitle =
        isPlaceholderTitle(rawTitle ?? '') || json['title_generated'] == true;
    return Session(
      id: id,
      title: displayTitle(
        title: rawTitle,
        preview: preview,
        startedAt: startedAt,
        id: id,
      ),
      model: json['model']?.toString() ?? 'Default',
      source: json['source']?.toString() ?? '',
      messageCount: _toInt(json['message_count']),
      isActive: endedAtRaw == null,
      preview: preview,
      startedAt: startedAt,
      endedAt: endedAt,
      hasGeneratedTitle: hasGeneratedTitle,
    );
  }

  static String _titleFromPreview(String? preview) {
    var cleaned = _collapseWhitespace(preview ?? '');
    if (cleaned.isEmpty) return '';
    cleaned = cleaned.replaceFirst(
      RegExp(r'^(user|assistant|hermes)\s*:\s*', caseSensitive: false),
      '',
    );
    return _truncateTitle(cleaned);
  }

  static String _titleFromStartedAt(double? startedAt) {
    if (startedAt == null || startedAt <= 0) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(
      (startedAt * 1000).round(),
    ).toLocal();
    return 'Chat ${_four(date.year)}-${_two(date.month)}-${_two(date.day)} '
        '${_two(date.hour)}:${_two(date.minute)}';
  }

  static String _shortId(String? id) {
    final cleaned = _collapseWhitespace(id ?? '');
    if (cleaned.isEmpty) return '';
    if (cleaned.length <= 8) return cleaned;
    return cleaned.substring(cleaned.length - 8);
  }

  static String _collapseWhitespace(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _truncateTitle(String title) {
    if (title.length <= _maxTitleLength) return title;
    return '${title.substring(0, _maxTitleLength - 3)}...';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  static String _four(int value) => value.toString().padLeft(4, '0');

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  static int _toInt(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
