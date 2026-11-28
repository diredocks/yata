import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:webview_all/webview_all.dart';

import '../../l10n/app_localizations.dart';
import '../../models/task_item.dart';
import '../../sync/microsoft/todo_wire_codecs.dart';

typedef RichNoteChangedCallback = void Function(
  String plainText,
  String html,
  String contentType,
);

class _EditorFormatState {
  const _EditorFormatState({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.bulletList = false,
    this.orderedList = false,
    this.headingLevel = 0,
    this.canUndo = false,
    this.canRedo = false,
    this.canUnlink = false,
  });

  factory _EditorFormatState.fromJson(Map<String, dynamic> json) {
    return _EditorFormatState(
      bold: json['bold'] as bool? ?? false,
      italic: json['italic'] as bool? ?? false,
      underline: json['underline'] as bool? ?? false,
      strike: json['strike'] as bool? ?? false,
      bulletList: json['bulletList'] as bool? ?? false,
      orderedList: json['orderedList'] as bool? ?? false,
      headingLevel: json['headingLevel'] as int? ?? 0,
      canUndo: json['canUndo'] as bool? ?? false,
      canRedo: json['canRedo'] as bool? ?? false,
      canUnlink: json['canUnlink'] as bool? ?? false,
    );
  }

  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;
  final bool bulletList;
  final bool orderedList;
  final int headingLevel;
  final bool canUndo;
  final bool canRedo;
  final bool canUnlink;
}

bool get isRichEditorWebViewSupported =>
    !kIsWeb &&
    (Platform.isAndroid || Platform.isLinux) &&
    WebViewPlatform.instance != null;

/// Full-screen rich-text note editor backed by `webview_all` + Tiptap, falling
/// back to a plain-text [TextField] when WebView is unavailable.
class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({
    super.key,
    required this.task,
    required this.onNoteSaved,
  });

  final TaskItem task;
  final RichNoteChangedCallback onNoteSaved;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen>
    with WidgetsBindingObserver {
  WebViewController? _webController;
  TextEditingController? _plainController;
  _EditorFormatState _formatState = const _EditorFormatState();
  bool _editorReady = false;
  bool _hasEdited = false;
  String _latestHtml = '';

  bool get _useWebView => isRichEditorWebViewSupported;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _latestHtml = widget.task.isHtmlNote
        ? widget.task.noteHtml
        : _escapePlainTextToHtml(widget.task.note);

    if (_useWebView) {
      _initWebView();
    } else {
      _plainController = TextEditingController(text: widget.task.note);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flushSave();
    _plainController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _flushSave();
    }
  }

  String _escapePlainTextToHtml(String text) {
    if (text.isEmpty) return '';
    final escaped = const HtmlEscape().convert(text);
    return '<p>${escaped.replaceAll('\n', '<br>')}</p>';
  }

  Future<void> _initWebView() async {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'YataBridge',
        onMessageReceived: (message) => _handleBridgeMessage(message.message),
      );
    _webController = controller;

    try {
      final htmlAsset = await rootBundle.loadString('assets/editor/index.html');
      if (!mounted) return;
      await controller.loadHtmlString(htmlAsset);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _webController = null;
        _plainController ??= TextEditingController(text: widget.task.note);
      });
    }
  }

  void _handleBridgeMessage(String raw) {
    if (!mounted) return;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return;

    switch (decoded['type']) {
      case 'ready':
        _editorReady = true;
        _sendInitToEditor();
      case 'formatState':
        final stateMap = decoded['state'];
        if (stateMap is Map<String, dynamic>) {
          setState(() {
            _formatState = _EditorFormatState.fromJson(stateMap);
          });
        }
      case 'contentChanged':
        _hasEdited = true;
        _latestHtml = decoded['html'] as String? ?? '';
    }
  }

  void _sendInitToEditor() {
    final controller = _webController;
    if (controller == null || !_editorReady || !mounted) return;

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final payload = jsonEncode({
      'html': _latestHtml,
      'editable': true,
      'placeholder': l10n.addNotePlaceholder,
      'theme': {
        'bg': _cssColor(theme.scaffoldBackgroundColor),
        'fg': _cssColor(theme.colorScheme.onSurface),
        'muted': _cssColor(theme.colorScheme.onSurfaceVariant),
        'accent': _cssColor(theme.colorScheme.primary),
        'isDark': theme.brightness == Brightness.dark,
      },
    });
    controller.runJavaScript('window.YataEditor?.init($payload);');
  }

  String _cssColor(Color color) {
    final r = (color.r * 255).round();
    final g = (color.g * 255).round();
    final b = (color.b * 255).round();
    final a = color.a.toStringAsFixed(3);
    return 'rgba($r, $g, $b, $a)';
  }

  void _execCommand(String cmd, [String? arg]) {
    final controller = _webController;
    if (controller == null || !_editorReady) return;
    final encodedCmd = jsonEncode(cmd);
    final encodedArg = arg == null ? 'undefined' : jsonEncode(arg);
    controller.runJavaScript(
      'window.YataEditor?.exec($encodedCmd, $encodedArg);',
    );
  }

  Future<void> _handleLinkAction() async {
    if (_formatState.canUnlink) {
      _execCommand('unsetLink');
      return;
    }
    final urlController = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext);
        return AlertDialog(
          title: const Text('Insert link'),
          content: TextField(
            controller: urlController,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(hintText: 'https://example.com'),
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(urlController.text),
              child: Text(l10n.save),
            ),
          ],
        );
      },
    );
    urlController.dispose();
    final trimmed = url?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    final normalized = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    _execCommand('setLink', normalized);
  }

  void _flushSave() {
    if (_plainController != null) {
      final text = _plainController!.text;
      if (text != widget.task.note) {
        widget.onNoteSaved(text, '', 'Text');
      }
      return;
    }
    if (!_hasEdited) return;
    _hasEdited = false;
    final normalizedDoc = normalizeHtmlBodyDocument(_latestHtml);
    if (normalizedDoc.isEmpty) {
      widget.onNoteSaved('', '', widget.task.noteContentType ?? 'HTML');
      return;
    }
    final plain = stripHtmlToPlainText(normalizedDoc, contentType: 'HTML');
    widget.onNoteSaved(plain, normalizedDoc, 'HTML');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _flushSave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.task.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: _webController != null
                  ? WebViewWidget(controller: _webController!)
                  : Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        controller: _plainController,
                        autofocus: true,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        style: theme.textTheme.bodyLarge,
                        decoration: InputDecoration(
                          hintText: l10n.addNotePlaceholder,
                          border: InputBorder.none,
                        ),
                      ),
                    ),
            ),
            if (_webController != null)
              _RichFormatBar(
                state: _formatState,
                onExec: _execCommand,
                onLinkTap: _handleLinkAction,
              ),
          ],
        ),
      ),
    );
  }
}

class _RichFormatBar extends StatelessWidget {
  const _RichFormatBar({
    required this.state,
    required this.onExec,
    required this.onLinkTap,
  });

  final _EditorFormatState state;
  final void Function(String cmd, [String? arg]) onExec;
  final VoidCallback onLinkTap;

  String get _headingLabel {
    return switch (state.headingLevel) {
      1 => 'Title',
      2 => 'Subhead',
      _ => 'Body',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeColor = theme.colorScheme.primary;
    final inactiveColor = theme.colorScheme.onSurfaceVariant;

    Widget formatButton({
      required IconData icon,
      required String tooltip,
      required bool active,
      VoidCallback? onPressed,
    }) {
      return IconButton(
        icon: Icon(icon, size: 20),
        tooltip: tooltip,
        color: active ? activeColor : inactiveColor,
        style: active
            ? IconButton.styleFrom(
                backgroundColor: activeColor.withValues(alpha: 0.12),
              )
            : null,
        onPressed: onPressed,
      );
    }

    return Material(
      elevation: 4,
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 48,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                PopupMenuButton<String>(
                  tooltip: 'Text style',
                  onSelected: (cmd) => onExec(cmd),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'paragraph', child: Text('Body')),
                    PopupMenuItem(
                      value: 'heading2',
                      child: Text(
                        'Subhead',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'heading1',
                      child: Text(
                        'Title',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _headingLabel,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: state.headingLevel > 0
                                ? activeColor
                                : inactiveColor,
                          ),
                        ),
                        Icon(
                          Icons.arrow_drop_down,
                          size: 18,
                          color: inactiveColor,
                        ),
                      ],
                    ),
                  ),
                ),
                const VerticalDivider(width: 12, indent: 10, endIndent: 10),
                formatButton(
                  icon: Icons.format_bold,
                  tooltip: 'Bold',
                  active: state.bold,
                  onPressed: () => onExec('bold'),
                ),
                formatButton(
                  icon: Icons.format_italic,
                  tooltip: 'Italic',
                  active: state.italic,
                  onPressed: () => onExec('italic'),
                ),
                formatButton(
                  icon: Icons.format_underlined,
                  tooltip: 'Underline',
                  active: state.underline,
                  onPressed: () => onExec('underline'),
                ),
                formatButton(
                  icon: Icons.format_strikethrough,
                  tooltip: 'Strikethrough',
                  active: state.strike,
                  onPressed: () => onExec('strike'),
                ),
                const VerticalDivider(width: 12, indent: 10, endIndent: 10),
                formatButton(
                  icon: Icons.undo,
                  tooltip: 'Undo',
                  active: false,
                  onPressed: state.canUndo ? () => onExec('undo') : null,
                ),
                formatButton(
                  icon: Icons.redo,
                  tooltip: 'Redo',
                  active: false,
                  onPressed: state.canRedo ? () => onExec('redo') : null,
                ),
                const VerticalDivider(width: 12, indent: 10, endIndent: 10),
                formatButton(
                  icon: Icons.format_list_bulleted,
                  tooltip: 'Bulleted list',
                  active: state.bulletList,
                  onPressed: () => onExec('bulletList'),
                ),
                formatButton(
                  icon: Icons.format_list_numbered,
                  tooltip: 'Numbered list',
                  active: state.orderedList,
                  onPressed: () => onExec('orderedList'),
                ),
                formatButton(
                  icon: state.canUnlink ? Icons.link_off : Icons.link,
                  tooltip: state.canUnlink ? 'Remove link' : 'Insert link',
                  active: state.canUnlink,
                  onPressed: onLinkTap,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
