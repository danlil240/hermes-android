// Chat screen with real-time streaming via REST API.
// Uses REST endpoints: POST /api/sessions/{id}/chat and
// GET /api/sessions/{id}/messages.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/active_runs_manager.dart';
import '../../core/models/question.dart';
import '../../core/network/connection_manager.dart';
import '../../core/network/background_chat_service.dart';
import '../../core/storage/session_cache.dart';
import '../questions/question_widgets.dart';
import '../../shared/responsive.dart';
import '../../shared/external_links.dart';
import '../../shared/widgets/code_highlighter.dart';
import 'package:uuid/uuid.dart';

class ChatScreen extends StatefulWidget {
  final SavedConnection connection;
  final Session session;

  const ChatScreen({
    required this.connection,
    required this.session,
    super.key,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  List<Map<String, dynamic>> _messages = [];
  final List<Map<String, dynamic>> _toolMessages = [];
  bool _loading = true;
  String? _error;
  bool _offline = false;
  late final ApiClient _client;
  late final GatewayChatClient _gateway;
  SessionCache? _cache;
  StreamSubscription<BackgroundChatEvent>? _backgroundChatEvents;

  // Chat sending state
  final _textController = TextEditingController();
  bool _sending = false;
  bool _streaming = false;

  // Draft protection: stores the text being sent so it can be restored in the
  // composer if the submission fails before reaching Hermes.
  String? _pendingDraft;

  // Voice input / spoken replies
  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  bool _speechAvailable = false;
  bool _listening = false;
  bool _voiceReplyEnabled = true;
  bool _awaitingVoiceReply = false;
  String? _voiceStatus;
  String? _sttLocaleId;

  // Verbose mode
  bool _verboseMode = false;

  // Current agent action for the activity card
  String? _currentAction;
  Timer? _elapsedTimer;

  // Active questions for this session (from SSE events or message history)
  final List<Question> _activeQuestions = [];

  // Scroll management
  final _scrollController = ScrollController();
  bool _showScrollToBottom = false;
  double _lastPixels = 0;
  static final Map<String, double> _savedPositions = {};

  String _currentTitle = '';
  bool _autoTitled = false;

  @override
  void initState() {
    super.initState();
    _currentTitle = widget.session.title;
    WidgetsBinding.instance.addObserver(this);
    _client = ApiClient(
      baseUrl: widget.connection.baseUrl,
      apiKey: widget.connection.apiKey,
      pathPrefix: widget.connection.gatewayPrefix ?? '',
      cfAccessClientId: widget.connection.cfAccessClientId,
      cfAccessClientSecret: widget.connection.cfAccessClientSecret,
    );
    _gateway = GatewayChatClient(_client);
    _backgroundChatEvents = BackgroundChatService.events.listen(
      _handleBackgroundChatEvent,
    );
    _initializeCacheAndFetch();
    _loadVerboseMode();
    _initVoice();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _loadVerboseMode() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _verboseMode = prefs.getBool('verbose_mode') ?? false);
  }

  @override
  void dispose() {
    _savedPositions[widget.session.id] = _lastPixels;
    WidgetsBinding.instance.removeObserver(this);
    _backgroundChatEvents?.cancel();
    _stopElapsedTimer();
    _speechToText.cancel();
    _flutterTts.stop();
    _client.close();
    _textController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      // A notification can resume the app after the Android foreground
      // service completed the server-owned run. The screen may have missed
      // the one-shot event while its Activity was stopped, so always reload
      // the authoritative server history when returning to the foreground.
      _fetchMessages(refreshAfterResume: true);
    }
  }

  Future<void> _initVoice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final voiceName = prefs.getString('voice_name');
      final voiceLocale = prefs.getString('voice_locale');

      if (voiceName != null && voiceName.isNotEmpty) {
        if (voiceName == voiceLocale) {
          await _flutterTts.setLanguage(voiceName);
        } else {
          await _flutterTts.setVoice({
            'name': voiceName,
            'locale': voiceLocale ?? '',
          });
        }
        _sttLocaleId = voiceLocale?.replaceAll('-', '_');
      } else {
        _sttLocaleId = null;
      }
      await _flutterTts.setSpeechRate(0.48);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      final available = await _speechToText.initialize(
        onStatus: _handleSpeechStatus,
        onError: _handleSpeechError,
      );
      if (!mounted) return;
      setState(() {
        _speechAvailable = available;
        _voiceStatus = available ? null : 'Speech recognition is unavailable';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _speechAvailable = false;
        _voiceStatus = 'Voice setup failed: $e';
      });
    }
  }

  void _handleSpeechStatus(String status) {
    if (!mounted) return;
    final listening = status == 'listening';
    setState(() {
      _listening = listening;
      if (!listening && status == 'done') {
        _voiceStatus = null;
      }
    });
  }

  void _handleSpeechError(SpeechRecognitionError error) {
    if (!mounted) return;
    setState(() {
      _listening = false;
      _voiceStatus = error.errorMsg;
    });
  }

  Future<void> _toggleVoiceInput() async {
    if (_streaming || _sending || _loading) return;
    if (_listening) {
      await _speechToText.stop();
      if (!mounted) return;
      setState(() => _listening = false);
      return;
    }

    if (!_speechAvailable) {
      await _initVoice();
      if (!_speechAvailable) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _voiceStatus ?? 'Speech recognition is unavailable',
              ),
            ),
          );
        }
        return;
      }
    }

    await _flutterTts.stop();
    if (!mounted) return;
    setState(() => _voiceStatus = 'Listening…');
    await _speechToText.listen(
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
        localeId: _sttLocaleId,
      ),
      onResult: _handleSpeechResult,
    );
  }

  void _handleSpeechResult(SpeechRecognitionResult result) {
    final recognised = result.recognizedWords.trim();
    if (recognised.isEmpty || !mounted) return;
    setState(() {
      _textController.text = recognised;
      _textController.selection = TextSelection.collapsed(
        offset: _textController.text.length,
      );
    });
    if (result.finalResult) {
      _sendMessage(speakResponse: true);
    }
  }

  Future<void> _speakAssistantText(String text) async {
    final spokenText = text.trim();
    if (spokenText.isEmpty || !_voiceReplyEnabled) return;
    await _flutterTts.stop();
    await _flutterTts.speak(spokenText);
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      _lastPixels = _scrollController.position.pixels;
    }
    final atBottom =
        _scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200;
    if (atBottom != !_showScrollToBottom) {
      setState(() => _showScrollToBottom = !atBottom);
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _initializeCacheAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    _cache = SessionCache(prefs, widget.connection.id);
    final cached = _cache!.loadMessages(widget.session.id);
    if (cached.isNotEmpty && mounted) {
      _extractToolMessages(cached);
      _extractQuestionBlocks(cached);
      setState(() {
        _messages = cached;
        _loading = false;
      });
    }
    await _fetchMessages();
  }

  Future<void> _fetchMessages({bool refreshAfterResume = false}) async {
    if (_messages.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final messages = await _client.getMessages(widget.session.id);
      if (!mounted) return;
      _extractToolMessages(messages);
      _extractQuestionBlocks(messages);
      await _fetchSessionQuestions();
      if (!mounted) return;
      // Reconcile delivery states: preserve locally-tracked failed and
      // incomplete messages that the server doesn't have yet, so the
      // user can still retry/reconnect after a refresh.
      final localPending = <Map<String, dynamic>>[];
      for (final m in _messages) {
        final state = m['deliveryState'] as String?;
        if (state == 'failed' || state == 'incomplete') {
          localPending.add(Map<String, dynamic>.from(m));
        }
      }
      if (localPending.isNotEmpty) {
        final serverUserContents = messages
            .where((m) => m['role'] == 'user')
            .map((m) => (m['content'] as String?) ?? '')
            .toSet();
        final serverAssistantContents = messages
            .where((m) => m['role'] == 'assistant')
            .map((m) => (m['content'] as String?) ?? '')
            .toSet();
        for (final m in localPending) {
          final content = (m['content'] as String?) ?? '';
          final role = m['role'] as String? ?? '';
          if (content.isEmpty) continue;
          final isInServer = role == 'user'
              ? serverUserContents.contains(content)
              : serverAssistantContents.contains(content);
          if (!isInServer) {
            messages.add(m);
          }
        }
      }
      setState(() {
        _messages = messages;
        _cache?.saveMessages(widget.session.id, messages);
        _offline = false;
        if (refreshAfterResume &&
            messages.isNotEmpty &&
            messages.last['role'] == 'assistant') {
          _streaming = false;
          _sending = false;
        }
        _loading = false;
      });
      _maybeAutoTitle();
      final saved = _savedPositions[widget.session.id];
      if (saved != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(
              saved.clamp(0.0, _scrollController.position.maxScrollExtent),
            );
          }
        });
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(
              _scrollController.position.maxScrollExtent,
            );
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      final errStr = e.toString();
      if (errStr.contains('404') || errStr.contains('not found')) {
        setState(() {
          _messages = [];
          _loading = false;
        });
        return;
      }
      if (_messages.isNotEmpty) {
        // We have cached messages — show stale-content banner
        setState(() {
          _offline = true;
          _loading = false;
          _error = null;
        });
      } else {
        setState(() {
          _error = errStr;
          _loading = false;
        });
      }
    }
  }

  void _handleBackgroundChatEvent(BackgroundChatEvent event) {
    if (!mounted || event.sessionId != widget.session.id || !_streaming) return;

    switch (event.type) {
      case 'token':
        final token = event.token;
        if (token == null || token.isEmpty) return;
        if (_currentAction == null ||
            _currentAction == 'Running on Hermes server') {
          setState(() => _currentAction = 'Generating response…');
          ActiveRunsManager.instance.updateChatRun(
            sessionId: widget.session.id,
            connectionId: widget.connection.id,
            connectionLabel: widget.connection.label,
            sessionTitle: _currentTitle,
            lastAction: 'Generating response…',
          );
        }
        setState(() {
          if (_messages.isNotEmpty && _messages.last['role'] == 'assistant') {
            _messages.last['content'] =
                (_messages.last['content'] as String) + token;
          }
        });
        return;
      case 'done':
        _completeBackgroundStream();
        return;
      case 'error':
        _handleBackgroundSendError(event.error ?? 'Background chat failed');
        return;
    }
  }

  /// Handle a background send error by finding the in-flight user message
  /// by its deliveryState (not text, since we may not have the text here)
  /// and marking it as failed. Also handles partial-result recovery for
  /// the assistant placeholder.
  void _handleBackgroundSendError(String error) {
    _completeRun(ActiveRunStatus.failed);
    setState(() {
      _sending = false;
      _streaming = false;
      _awaitingVoiceReply = false;
      // Find the user message with deliveryState 'sending'
      for (var i = _messages.length - 1; i >= 0; i--) {
        final m = _messages[i];
        if (m['role'] == 'user' && m['deliveryState'] == 'sending') {
          m['deliveryState'] = 'failed';
          m['error'] = error;
          break;
        }
      }
      // Partial-result recovery for assistant message
      if (_messages.isNotEmpty && _messages.last['role'] == 'assistant') {
        final assistantContent = _messages.last['content'] as String? ?? '';
        if (assistantContent.isNotEmpty) {
          _messages.last['deliveryState'] = 'incomplete';
          _messages.last['error'] = error;
        } else {
          _messages.removeLast();
        }
      }
      // Draft protection: restore text to composer
      if (_pendingDraft != null) {
        _textController.text = _pendingDraft!;
        _textController.selection = TextSelection.collapsed(
          offset: _textController.text.length,
        );
        _pendingDraft = null;
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Send failed: $error'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  Future<void> _completeBackgroundStream() async {
    // Message reached Hermes — clear draft protection.
    _pendingDraft = null;
    try {
      final messages = await _client.getMessages(widget.session.id);
      if (!mounted) return;
      _extractToolMessages(messages);
      _extractQuestionBlocks(messages);
      await _fetchSessionQuestions();
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _cache?.saveMessages(widget.session.id, messages);
        _streaming = false;
        _sending = false;
        _showScrollToBottom = false;
      });
      _completeRun(ActiveRunStatus.completed);
      _maybeAutoTitle();
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _streaming = false;
        _sending = false;
      });
      _completeRun(ActiveRunStatus.completed);
    }
  }

  void _extractToolMessages(List<Map<String, dynamic>> messages) {
    _toolMessages.clear();
    for (final msg in messages) {
      final role = (msg['role'] as String?) ?? '';
      if (role != 'tool') continue;

      final name =
          (msg['name'] as String?) ??
          (msg['tool_name'] as String?) ??
          (msg['toolCallName'] as String?) ??
          '';
      final toolCallId = (msg['tool_call_id'] as String?) ?? '';
      final content = (msg['content'] as String?) ?? '';

      String toolName = name.isNotEmpty ? name : '';
      if (toolName.isEmpty && content.isNotEmpty) {
        final match = RegExp(r'source="([^"]+)"').firstMatch(content);
        if (match != null) toolName = match.group(1)!;
      }
      if (toolName.isEmpty) toolName = 'tool';

      final emoji = _toolEmoji(toolName);
      _toolMessages.add({
        'role': 'tool_progress',
        'content': '$emoji $toolName — done',
        'toolCallId': toolCallId,
        'status': 'completed',
        'tool': toolName,
      });
    }
  }

  String _toolEmoji(String toolName) {
    switch (toolName) {
      case 'browser_navigate':
      case 'browser_console':
      case 'browser':
        return '🌐';
      case 'read_file':
      case 'read':
        return '📄';
      case 'write_file':
      case 'write':
        return '✏️';
      case 'search':
      case 'google_search':
        return '🔍';
      case 'execute':
      case 'shell':
        return '💻';
      case 'think':
      case 'reasoning':
        return '🧠';
      default:
        return '🔧';
    }
  }

  /// Extract question blocks from message history.
  ///
  /// The Gateway may embed question blocks in messages using:
  /// - A `type` field (e.g. `choice_question`, `confirmation_question`)
  /// - A `question` field containing the question payload
  /// - A `blocks` array containing typed blocks
  void _extractQuestionBlocks(List<Map<String, dynamic>> messages) {
    for (final msg in messages) {
      final type = (msg['type'] as String?) ?? '';
      if (_isQuestionType(type)) {
        _upsertQuestion(Question.fromJson(msg));
        continue;
      }
      final questionField = msg['question'];
      if (questionField is Map<String, dynamic>) {
        _upsertQuestion(Question.fromJson(questionField));
        continue;
      }
      final blocks = msg['blocks'];
      if (blocks is List) {
        for (final block in blocks) {
          if (block is Map<String, dynamic>) {
            final blockType = (block['type'] as String?) ?? '';
            if (_isQuestionType(blockType)) {
              _upsertQuestion(Question.fromJson(block));
            }
          }
        }
      }
    }
  }

  bool _isQuestionType(String type) {
    return type == 'choice_question' ||
        type == 'confirmation_question' ||
        type == 'text_input_question' ||
        type == 'number_question' ||
        type == 'date_time_question';
  }

  /// Fetch pending questions for this session from the API.
  Future<void> _fetchSessionQuestions() async {
    try {
      final rawQuestions = await _client.getSessionQuestions(widget.session.id);
      for (final q in rawQuestions) {
        _upsertQuestion(Question.fromJson(q));
      }
    } catch (_) {
      // Session questions endpoint may not exist on all backends — ignore.
    }
  }

  void _upsertQuestion(Question question) {
    final idx = _activeQuestions.indexWhere((q) => q.id == question.id);
    if (idx >= 0) {
      _activeQuestions[idx] = question;
    } else {
      _activeQuestions.add(question);
    }
    if (question.id.isEmpty) return;
    ActiveRunsManager.instance.updateQuestion(
      questionId: question.id,
      sessionId: question.sessionId.isNotEmpty
          ? question.sessionId
          : widget.session.id,
      connectionId: widget.connection.id,
      connectionLabel: widget.connection.label,
      sessionTitle: _currentTitle,
      questionText: question.title.isNotEmpty
          ? question.title
          : 'Pending question',
      resolved: !question.isPending,
    );
  }

  /// Handle a hermes.question SSE event during streaming.
  void _handleQuestionSseEvent(Map<String, dynamic> data) {
    if (!mounted) return;
    final question = Question.fromJson(data);
    setState(() => _upsertQuestion(question));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  /// Answer a question and update its state.
  Future<void> _handleQuestionAnswer(
    String questionId,
    Map<String, dynamic> answer,
  ) async {
    try {
      final result = await _client.answerQuestion(questionId, answer);
      if (!mounted) return;
      final updated = Question.fromJson(result);
      setState(() => _upsertQuestion(updated));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to answer question: $e'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  /// Generate a client-side submission ID for idempotent retries.
  /// The server can use this to deduplicate agent runs when a retry
  /// sends the same prompt after a network hiccup.
  String _generateSubmissionId() {
    return 'sub-${DateTime.now().millisecondsSinceEpoch}-${const Uuid().v4()}';
  }

  /// Send message via SSE streaming (Gateway API Server).
  ///
  /// [retryText] and [retrySubmissionId] are set when retrying a failed
  /// message — the text and submission ID from the original attempt are
  /// reused so the server can deduplicate the run.
  Future<void> _sendMessage({
    bool speakResponse = false,
    String? retryText,
    String? retrySubmissionId,
  }) async {
    final text = (retryText ?? _textController.text).trim();
    if (text.isEmpty) return;
    if (_sending || _streaming) return;

    // Draft protection: store the text so it can be restored if the
    // submission fails before reaching Hermes.
    if (retryText == null) {
      _pendingDraft = text;
    }
    _textController.text = '';
    _awaitingVoiceReply = speakResponse && _voiceReplyEnabled;

    final submissionId = retrySubmissionId ?? _generateSubmissionId();

    // Build conversation history, excluding failed/incomplete messages
    final history = <Map<String, dynamic>>[];
    for (var i = _messages.length - 1; i >= 0; i--) {
      final m = _messages[i];
      final state = m['deliveryState'] as String?;
      if (state == 'failed' || state == 'incomplete') continue;
      history.add({'role': m['role'] ?? 'user', 'content': m['content'] ?? ''});
    }

    setState(() {
      _sending = true;
      _streaming = true;
      _showScrollToBottom = false;
      _currentAction = null;
      _messages.add({
        'role': 'user',
        'content': text,
        'deliveryState': 'sending',
        'submissionId': submissionId,
      });
      _messages.add({
        'role': 'assistant',
        'content': '',
        'deliveryState': 'running',
      });
    });

    _startElapsedTimer();
    ActiveRunsManager.instance.updateChatRun(
      sessionId: widget.session.id,
      connectionId: widget.connection.id,
      connectionLabel: widget.connection.label,
      sessionTitle: _currentTitle,
      status: ActiveRunStatus.running,
      lastAction: 'Sending message…',
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    // Android submits a server-owned run. The foreground service only polls
    // status for a notification; the Hermes server owns execution and keeps
    // it alive after the app or phone disconnects.
    final startedInBackground = await _gateway.startMessageInBackground(
      message: text,
      sessionId: widget.session.id,
      history: history,
      submissionId: submissionId,
    );
    if (startedInBackground) {
      // Message reached Hermes — clear draft protection.
      _pendingDraft = null;
      ActiveRunsManager.instance.updateChatRun(
        sessionId: widget.session.id,
        connectionId: widget.connection.id,
        connectionLabel: widget.connection.label,
        sessionTitle: _currentTitle,
        status: ActiveRunStatus.running,
        lastAction: 'Running on Hermes server',
      );
      return;
    }

    // Accumulate tokens into the streaming placeholder
    await _gateway.sendMessageStreaming(
      message: text,
      sessionId: widget.session.id,
      history: history,
      submissionId: submissionId,
      onToken: (token) {
        if (!mounted) return;
        setState(() {
          if (_messages.isNotEmpty && _messages.last['role'] == 'assistant') {
            _messages.last['content'] =
                (_messages.last['content'] as String) + token;
          }
        });
        if (_currentAction == null || _currentAction == 'Sending message…') {
          setState(() => _currentAction = 'Generating response…');
          ActiveRunsManager.instance.updateChatRun(
            sessionId: widget.session.id,
            connectionId: widget.connection.id,
            connectionLabel: widget.connection.label,
            sessionTitle: _currentTitle,
            lastAction: 'Generating response…',
          );
        }
      },
      onToolProgress: (progress) {
        if (!mounted) return;
        _upsertToolProgress(progress);
      },
      onQuestion: (data) {
        _handleQuestionSseEvent(data);
      },
      onDone: () async {
        if (!mounted) return;
        // Message was sent successfully — clear draft protection.
        _pendingDraft = null;
        // Refresh messages to get the final server-side state
        try {
          final messages = await _client.getMessages(widget.session.id);
          if (!mounted) return;
          _extractToolMessages(messages);
          _extractQuestionBlocks(messages);
          await _fetchSessionQuestions();
          if (!mounted) return;
          setState(() {
            _messages = messages;
            _cache?.saveMessages(widget.session.id, messages);
            _streaming = false;
            _sending = false;
            _showScrollToBottom = false;
          });
          _completeRun(ActiveRunStatus.completed);
          _maybeAutoTitle();
          if (_awaitingVoiceReply) {
            _awaitingVoiceReply = false;
            final assistant = messages.reversed.firstWhere(
              (message) => message['role'] == 'assistant',
              orElse: () => const <String, dynamic>{},
            );
            final assistantText = assistant['content']?.toString();
            if (assistantText != null) {
              await _speakAssistantText(assistantText);
            }
          }
          final saved = _savedPositions[widget.session.id];
          if (saved != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_scrollController.hasClients) {
                _scrollController.jumpTo(
                  saved.clamp(0.0, _scrollController.position.maxScrollExtent),
                );
              }
            });
          } else {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_scrollController.hasClients) {
                _scrollController.jumpTo(
                  _scrollController.position.maxScrollExtent,
                );
              }
            });
          }
        } catch (e) {
          setState(() {
            _streaming = false;
            _sending = false;
          });
          _completeRun(ActiveRunStatus.completed);
        }
      },
      onError: (error) {
        if (!mounted) return;
        // Partial-result recovery: if the assistant placeholder has
        // received some tokens before the disconnect, retain it as
        // incomplete rather than discarding it.
        setState(() {
          if (_messages.isNotEmpty && _messages.last['role'] == 'assistant') {
            final assistantContent = _messages.last['content'] as String? ?? '';
            if (assistantContent.isNotEmpty) {
              _messages.last['deliveryState'] = 'incomplete';
              _messages.last['error'] = error;
            } else {
              _messages.removeLast();
            }
          }
        });
        _handleSendError(text, error, submissionId: submissionId);
      },
    );
  }

  void _handleSendError(String text, Object e, {String? submissionId}) {
    _completeRun(ActiveRunStatus.failed);
    setState(() {
      _sending = false;
      _streaming = false;
      _awaitingVoiceReply = false;
      // Mark the user message as failed instead of removing it, so the
      // user can see the prompt, the error, and retry/edit/copy it.
      for (var i = _messages.length - 1; i >= 0; i--) {
        final m = _messages[i];
        if (m['role'] == 'user' &&
            m['content'] == text &&
            m['deliveryState'] == 'sending') {
          m['deliveryState'] = 'failed';
          m['error'] = e.toString();
          if (submissionId != null) m['submissionId'] = submissionId;
          break;
        }
      }
      // Draft protection: restore the text in the composer so the user
      // doesn't lose their input if the message never reached Hermes.
      if (_pendingDraft != null) {
        _textController.text = _pendingDraft!;
        _textController.selection = TextSelection.collapsed(
          offset: _textController.text.length,
        );
        _pendingDraft = null;
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Send failed: $e'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  /// Retry a failed user message. Removes the failed message and any
  /// incomplete assistant response after it, then resends with the
  /// same submission ID so the server can deduplicate the run.
  void _retryMessage(Map<String, dynamic> failedMsg) {
    if (failedMsg['deliveryState'] != 'failed') return;
    final failedIndex = _messages.indexWhere((m) => identical(m, failedMsg));
    if (failedIndex < 0) return;

    final text = failedMsg['content'] as String? ?? '';
    final submissionId = failedMsg['submissionId'] as String?;

    // Remove the failed user message and any incomplete assistant
    // message that follows it.
    setState(() {
      _messages.removeAt(failedIndex);
      if (failedIndex < _messages.length) {
        final next = _messages[failedIndex];
        if (next['role'] == 'assistant' &&
            next['deliveryState'] == 'incomplete') {
          _messages.removeAt(failedIndex);
        }
      }
    });

    _sendMessage(retryText: text, retrySubmissionId: submissionId);
  }

  /// Edit a failed user message. Puts the text back in the composer
  /// and removes the failed message so the user can edit and resend.
  void _editMessage(Map<String, dynamic> failedMsg) {
    if (failedMsg['deliveryState'] != 'failed') return;
    final failedIndex = _messages.indexWhere((m) => identical(m, failedMsg));
    if (failedIndex < 0) return;

    final text = failedMsg['content'] as String? ?? '';

    setState(() {
      _messages.removeAt(failedIndex);
      if (failedIndex < _messages.length) {
        final next = _messages[failedIndex];
        if (next['role'] == 'assistant' &&
            next['deliveryState'] == 'incomplete') {
          _messages.removeAt(failedIndex);
        }
      }
      _textController.text = text;
      _textController.selection = TextSelection.collapsed(
        offset: _textController.text.length,
      );
    });
  }

  /// Reconnect to the server to fetch the latest state after a stream
  /// disconnect left a partial (incomplete) assistant response.
  Future<void> _reconnectStream() async {
    setState(() {
      _streaming = true;
      _sending = true;
    });
    try {
      await _fetchMessages();
    } finally {
      if (mounted) {
        setState(() {
          _streaming = false;
          _sending = false;
        });
      }
    }
  }

  void _upsertToolProgress(Map<String, dynamic> progress) {
    final toolCallId =
        progress['toolCallId']?.toString() ??
        progress['tool_call_id']?.toString() ??
        progress['id']?.toString() ??
        '';
    final tool = progress['tool']?.toString() ?? 'tool';
    final status = progress['status']?.toString() ?? 'running';
    final emoji = progress['emoji']?.toString() ?? '🔧';
    final label = progress['label']?.toString();
    final display = label == null || label.isEmpty ? tool : label;
    final done = status == 'completed' || status == 'finished';
    final content = done
        ? '$emoji $display — done'
        : '$emoji $display — $status';

    setState(() {
      _currentAction = '$emoji $display';
      final idx = toolCallId.isEmpty
          ? -1
          : _toolMessages.indexWhere((m) => m['toolCallId'] == toolCallId);
      final payload = {
        'role': 'tool_progress',
        'content': content,
        'toolCallId': toolCallId,
        'status': status,
        'tool': tool,
      };
      if (idx >= 0) {
        _toolMessages[idx] = payload;
      } else {
        _toolMessages.add(payload);
      }
    });

    ActiveRunsManager.instance.updateChatRun(
      sessionId: widget.session.id,
      connectionId: widget.connection.id,
      connectionLabel: widget.connection.label,
      sessionTitle: _currentTitle,
      lastAction: '$emoji $display',
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _streaming) setState(() {});
    });
  }

  void _stopElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
  }

  void _completeRun(ActiveRunStatus status) {
    _stopElapsedTimer();
    setState(() => _currentAction = null);
    ActiveRunsManager.instance.updateChatRun(
      sessionId: widget.session.id,
      connectionId: widget.connection.id,
      connectionLabel: widget.connection.label,
      sessionTitle: _currentTitle,
      status: status,
    );
  }

  void _maybeAutoTitle() {
    if (_autoTitled) return;
    if (!Session.isAutoTitleCandidate(widget.session, _currentTitle)) return;
    final userMsgs = _messages.where((m) => m['role'] == 'user').toList();
    if (userMsgs.isEmpty) return;
    _autoTitled = true;
    final firstContent = (userMsgs.first['content'] as String?) ?? '';
    if (firstContent.isEmpty) return;
    final cleaned = firstContent.replaceAll(RegExp(r'\s+'), ' ').trim();
    final title = cleaned.length > 50
        ? '${cleaned.substring(0, 50)}…'
        : cleaned;
    _currentTitle = title;
    setState(() {});
    _client
        .updateSession(widget.session.id, title: title)
        .catchError((_) {});
  }

  String _exportTranscript() {
    final lines = <String>[];
    lines.add('# $_currentTitle');
    lines.add('');
    lines.add('Session ID: ${widget.session.id}');
    lines.add('Model: ${widget.session.model}');
    lines.add('');
    for (final msg in _messages) {
      final role = (msg['role'] as String?) ?? 'unknown';
      final content = (msg['content'] as String?) ?? '';
      if (content.isEmpty) continue;
      if (role == 'user') {
        lines.add('**User:** $content');
      } else if (role == 'assistant') {
        lines.add('**Hermes:** $content');
      } else if (role == 'tool') {
        final name = (msg['name'] as String?) ?? 'tool';
        lines.add('**Tool ($name):** $content');
      }
      lines.add('');
    }
    return lines.join('\n');
  }

  void _shareTranscript() {
    final transcript = _exportTranscript();
    Share.share(transcript, subject: 'Hermes Chat: $_currentTitle');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _currentTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_offline)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.cloud_off, color: Colors.orange, size: 20),
            ),
          if (_streaming)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: _loading ? null : _shareTranscript,
              tooltip: 'Export chat',
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loading ? null : _fetchMessages,
              tooltip: 'Refresh',
            ),
          ],
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Responsive.isTablet(context) ? 800 : double.infinity,
          ),
          child: Column(
            children: [
              if (_offline) _buildOfflineBanner(),
              if (_streaming) _buildAgentActivityCard(),
              Expanded(child: _buildBody()),
              _buildInputBar(),
            ],
          ),
        ),
      ),
      floatingActionButton: _showScrollToBottom
          ? FloatingActionButton.small(
              onPressed: _scrollToBottom,
              tooltip: 'Scroll to bottom',
              child: const Icon(Icons.keyboard_arrow_down),
            )
          : null,
    );
  }

  Widget _buildAgentActivityCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final run = ActiveRunsManager.instance.chatRunFor(
      widget.connection.id,
      widget.session.id,
    );
    final elapsed = run?.elapsedLabel ?? '0s';
    final action = _currentAction ?? 'Running on Hermes server';

    return Material(
      color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.2),
            ),
          ),
        ),
        child: Row(
          children: [
            // Pulsing server icon
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFFD4AF37),
              ),
            ),
            const SizedBox(width: 12),
            // Center: server + current action
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.dns, size: 11, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text(
                        'Running on Hermes server',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[500],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        elapsed,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[400],
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    action,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // "Leave safely" reassurance chip
            Tooltip(
              message: 'Your work continues on the server even if you leave',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 12,
                      color: Colors.green.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Safe to leave',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.green.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(blurRadius: 4, color: Colors.black.withValues(alpha: 0.1)),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                decoration: InputDecoration(
                  hintText: _offline
                      ? 'Offline — sending unavailable'
                      : 'Type a message…',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  isDense: true,
                ),
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.send,
                enabled: !_loading && !_streaming && !_offline,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              icon: Icon(_listening ? Icons.mic_off : Icons.mic),
              color: _listening ? Theme.of(context).colorScheme.error : null,
              onPressed: (!_loading && !_streaming && !_sending && !_offline)
                  ? _toggleVoiceInput
                  : null,
              tooltip: _listening ? 'Stop listening' : 'Speak to Hermes',
            ),
            IconButton(
              icon: Icon(
                _voiceReplyEnabled ? Icons.volume_up : Icons.volume_off,
              ),
              onPressed: () {
                setState(() => _voiceReplyEnabled = !_voiceReplyEnabled);
                if (!_voiceReplyEnabled) {
                  _flutterTts.stop();
                }
              },
              tooltip: _voiceReplyEnabled
                  ? 'Spoken replies on'
                  : 'Spoken replies off',
            ),
            const SizedBox(width: 4),
            CircleAvatar(
              child: _streaming
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      icon: const Icon(Icons.send, size: 20),
                      onPressed: _offline ? null : _sendMessage,
                      tooltip: 'Send',
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineBanner() {
    final syncedAt = _cache?.messagesSyncedAt(widget.session.id);
    final syncLabel = syncedAt != null
        ? 'showing messages synced ${_formatRelativeTime(syncedAt)}'
        : 'showing cached messages';
    return Material(
      color: const Color(0xFF2D2D2D),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.cloud_off, color: Colors.orange, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Offline — $syncLabel',
                style: const TextStyle(
                  color: Colors.orange,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.orange, size: 18),
              tooltip: 'Retry',
              onPressed: _fetchMessages,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  String _formatRelativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber, size: 48, color: Colors.orange),
              const SizedBox(height: 16),
              Text(
                'Failed to load messages',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _fetchMessages,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // Build display list: consecutive tool messages grouped into cards,
    // interleaved with user/assistant bubbles.
    final toolQueue = List<Map<String, dynamic>>.from(_toolMessages);
    final displayMessages = <dynamic>[];
    final currentGroup = <Map<String, dynamic>>[];

    for (final msg in _messages) {
      final role = (msg['role'] as String?) ?? 'assistant';
      if (role == 'tool') {
        if (toolQueue.isNotEmpty) {
          currentGroup.add(toolQueue.removeAt(0));
        }
        continue;
      }
      if (role != 'user' && role != 'assistant') continue;
      final content = (msg['content'] as String?) ?? '';
      final deliveryState = msg['deliveryState'] as String?;
      // Skip empty messages that don't have a delivery state (e.g. the
      // initial assistant placeholder before any tokens arrive is
      // still shown via 'running' state).
      if (content.isEmpty && deliveryState == null) continue;

      if (currentGroup.isNotEmpty) {
        displayMessages.add(currentGroup.toList());
        currentGroup.clear();
      }
      displayMessages.add(msg);
    }
    if (currentGroup.isNotEmpty) {
      displayMessages.add(currentGroup.toList());
    }

    // Tools from SSE events that arrived during streaming but haven't been
    // matched to server messages yet — show them as a card.
    if (toolQueue.isNotEmpty) {
      displayMessages.add(toolQueue.toList());
    }

    // Append pending question cards after messages
    final pendingQuestions = _activeQuestions
        .where((q) => q.isPending)
        .toList();
    for (final q in pendingQuestions) {
      displayMessages.add(q);
    }

    // Empty state: no messages and no pending questions
    if (displayMessages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_outlined, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No messages yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Send a message below to start chatting',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: displayMessages.length,
      itemBuilder: (context, index) {
        final item = displayMessages[index];

        if (item is List<Map<String, dynamic>>) {
          return _ToolProgressCard(items: item, verbose: _verboseMode);
        }

        if (item is Question) {
          return QuestionCard(
            question: item,
            onAnswer: _handleQuestionAnswer,
            enabled: !_streaming,
          );
        }

        final msg = item as Map<String, dynamic>;
        final role = (msg['role'] as String?) ?? 'assistant';
        final content = (msg['content'] as String?) ?? '';
        final isUser = role == 'user';
        final deliveryState = msg['deliveryState'] as String?;

        return _MessageBubble(
          content: content,
          isUser: isUser,
          verbose: _verboseMode,
          metadata: msg,
          onRetry: isUser && deliveryState == 'failed'
              ? () => _retryMessage(msg)
              : null,
          onEdit: isUser && deliveryState == 'failed'
              ? () => _editMessage(msg)
              : null,
          onReconnect: !isUser && deliveryState == 'incomplete'
              ? () => _reconnectStream()
              : null,
        );
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final String content;
  final bool isUser;
  final bool verbose;
  final Map<String, dynamic> metadata;
  final VoidCallback? onRetry;
  final VoidCallback? onEdit;
  final VoidCallback? onReconnect;

  const _MessageBubble({
    required this.content,
    required this.isUser,
    this.verbose = false,
    this.metadata = const {},
    this.onRetry,
    this.onEdit,
    this.onReconnect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Bubble colors
    final userBubbleColor = const Color(0xFFD4AF37);
    final assistantBubbleColor = isDark
        ? const Color(0xFF2A2A2A)
        : const Color(0xFFEAEAEA);
    final assistantTextColor = isDark ? Colors.white : Colors.black87;

    // Collect extra metadata for verbose mode
    final List<String> metaLines = [];
    if (verbose) {
      final role = (metadata['role'] as String?) ?? 'unknown';
      metaLines.add('role: $role');
      // Show any extra fields that aren't role/content
      for (final entry in metadata.entries) {
        if (entry.key == 'role' || entry.key == 'content') continue;
        final value = entry.value?.toString() ?? 'null';
        if (value.length > 80) {
          metaLines.add('${entry.key}: ${value.substring(0, 80)}…');
        } else {
          metaLines.add('${entry.key}: $value');
        }
      }
    }

    final bubble = Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width - 80,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isUser ? userBubbleColor : assistantBubbleColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Verbose metadata header
          if (metaLines.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (isUser ? Colors.white : Colors.black).withValues(
                  alpha: 0.1,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: metaLines
                    .map(
                      (line) => Text(
                        line,
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: isUser
                              ? Colors.white.withValues(alpha: 0.8)
                              : (isDark ? Colors.grey[400] : Colors.grey[600]),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
          // Message content
          MarkdownBody(
            data: content,
            onTapLink: (_, href, _) async {
              if (href != null) {
                await openExternalLink(href);
              }
            },
            syntaxHighlighter: isUser ? null : CodeHighlighter(isDark: isDark),
            styleSheet: MarkdownStyleSheet(
              p: (isUser
                  ? theme.textTheme.bodyMedium?.copyWith(color: Colors.white)
                  : theme.textTheme.bodyMedium?.copyWith(
                      color: assistantTextColor,
                    )),
              code: TextStyle(
                backgroundColor: (isUser ? Colors.white : Colors.black)
                    .withValues(alpha: 0.12),
                fontFamily: 'monospace',
                color: isUser ? Colors.white : null,
              ),
              codeblockDecoration: BoxDecoration(
                color: isUser
                    ? Colors.white.withValues(alpha: 0.12)
                    : (isDark
                          ? const Color(0xFF282C34)
                          : const Color(0xFFFAFAFA)),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isUser
                      ? Colors.white24
                      : (isDark
                            ? Colors.white12
                            : Colors.black.withValues(alpha: 0.08)),
                ),
              ),
              codeblockPadding: const EdgeInsets.all(12),
              a: TextStyle(
                color: isUser ? Colors.white70 : theme.colorScheme.primary,
              ),
              h1: isUser
                  ? theme.textTheme.headlineSmall?.copyWith(color: Colors.white)
                  : theme.textTheme.headlineSmall,
              h2: isUser
                  ? theme.textTheme.titleLarge?.copyWith(color: Colors.white)
                  : theme.textTheme.titleLarge,
              h3: isUser
                  ? theme.textTheme.titleMedium?.copyWith(color: Colors.white)
                  : theme.textTheme.titleMedium,
              blockquote: TextStyle(
                color: isUser ? Colors.white60 : Colors.grey,
                fontStyle: FontStyle.italic,
              ),
              blockquoteDecoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: isUser ? Colors.white38 : theme.colorScheme.primary,
                    width: 3,
                  ),
                ),
              ),
              em: isUser
                  ? theme.textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: Colors.white,
                    )
                  : theme.textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
              strong: isUser
                  ? theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    )
                  : theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
            ),
          ),
          // Delivery state UI
          ..._buildDeliveryStateWidgets(theme, isDark),
        ],
      ),
    );

    return Row(
      mainAxisAlignment: isUser
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [bubble],
    );
  }

  List<Widget> _buildDeliveryStateWidgets(ThemeData theme, bool isDark) {
    final deliveryState = metadata['deliveryState'] as String?;
    if (deliveryState == null) return const [];

    switch (deliveryState) {
      case 'sending':
        return [
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: isUser
                      ? Colors.white70
                      : (isDark ? Colors.white54 : Colors.black54),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Sending…',
                style: TextStyle(
                  fontSize: 11,
                  color: isUser
                      ? Colors.white70
                      : (isDark ? Colors.white54 : Colors.black54),
                ),
              ),
            ],
          ),
        ];

      case 'failed':
        final error = metadata['error']?.toString() ?? 'Unknown error';
        return [
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: isUser ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.error_outline, size: 14, color: Colors.red[300]),
                    const SizedBox(width: 4),
                    Text(
                      'Failed to send',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.red[300],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  error,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: isUser
                        ? Colors.white60
                        : (isDark ? Colors.white54 : Colors.black54),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (onRetry != null)
                _ActionChip(
                  label: 'Retry',
                  icon: Icons.refresh,
                  onTap: onRetry!,
                  isUser: isUser,
                  isDark: isDark,
                ),
              if (onEdit != null)
                _ActionChip(
                  label: 'Edit',
                  icon: Icons.edit_outlined,
                  onTap: onEdit!,
                  isUser: isUser,
                  isDark: isDark,
                ),
              _ActionChip(
                label: 'Copy',
                icon: Icons.copy_outlined,
                onTap: () {
                  Clipboard.setData(ClipboardData(text: content));
                },
                isUser: isUser,
                isDark: isDark,
              ),
            ],
          ),
        ];

      case 'incomplete':
        final error = metadata['error']?.toString();
        return [
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber,
                      size: 14,
                      color: Colors.orange[300],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Incomplete — stream disconnected',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange[300],
                      ),
                    ),
                  ],
                ),
                if (error != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    error,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onReconnect != null) ...[
            const SizedBox(height: 6),
            _ActionChip(
              label: 'Reconnect',
              icon: Icons.cloud_sync_outlined,
              onTap: onReconnect!,
              isUser: isUser,
              isDark: isDark,
            ),
          ],
        ];

      default:
        return const [];
    }
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isUser;
  final bool isDark;

  const _ActionChip({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.isUser,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isUser
              ? Colors.white.withValues(alpha: 0.15)
              : (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isUser
                  ? Colors.white70
                  : (isDark ? Colors.white60 : Colors.black54),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: isUser
                    ? Colors.white70
                    : (isDark ? Colors.white60 : Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolProgressCard extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final bool verbose;

  const _ToolProgressCard({required this.items, this.verbose = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFEAEAEA);
    final fg = isDark ? Colors.white70 : Colors.black54;

    final active = items.any((item) {
      final status = (item['status'] as String?) ?? '';
      return status != 'completed' && status != 'finished';
    });

    final emojis = items.map((item) {
      final content = (item['content'] as String?) ?? '';
      return content.isNotEmpty
          ? content.substring(0, content.length < 2 ? content.length : 2)
          : '\uD83D\uDD27';
    }).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width - 80,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Text(
            active ? '\u23F3' : '\u2705',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(width: 6),
          Text(emojis.join(' '), style: const TextStyle(fontSize: 13)),
          if (active)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: fg),
              ),
            ),
        ],
      ),
    );
  }
}
