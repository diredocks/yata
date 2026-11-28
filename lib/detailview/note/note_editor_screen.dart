import 'dart:async';
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
  bool _closing = false;
  String _initialHtml = '';
  String _latestHtml = '';

  bool get _useWebView => isRichEditorWebViewSupported;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialHtml = widget.task.isHtmlNote
        ? widget.task.noteHtml
        : _escapePlainTextToHtml(widget.task.note);
    _latestHtml = _initialHtml;

    if (_useWebView) {
      unawaited(_initWebView());
    } else {
      _plainController = TextEditingController(text: widget.task.note);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flushSave();
    final controller = _webController;
    _webController = null;
    if (controller != null) {
      unawaited(controller.platform.closeWebViewSession().catchError((_) {}));
    }
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
    try {
      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      try {
        await controller.setBackgroundColor(Colors.transparent);
      } catch (_) {}
      await controller.addJavaScriptChannel(
        'YataBridge',
        onMessageReceived: (message) => _handleBridgeMessage(message.message),
      );
      final htmlAsset = await rootBundle.loadString('assets/editor/index.html');
      if (!mounted || _closing) {
        unawaited(controller.platform.closeWebViewSession().catchError((_) {}));
        return;
      }
      setState(() => _webController = controller);
      await controller.loadHtmlString(htmlAsset);
    } catch (_) {
      if (!mounted || _closing) return;
      setState(() {
        _webController = null;
        _plainController ??= TextEditingController(text: widget.task.note);
      });
    }
  }

  void _handleBridgeMessage(String raw) {
    if (!mounted || _closing) return;
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
    if (controller == null || !_editorReady || !mounted || _closing) return;

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
    }).replaceAll('\u2028', r'\u2028').replaceAll('\u2029', r'\u2029');
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
    if (controller == null || !_editorReady || _closing) return;
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

  Future<void> _pullLatestContentFromWebView() async {
    final controller = _webController;
    if (controller == null || !_editorReady) return;
    try {
      final raw = await controller
          .runJavaScriptReturningResult(
            'JSON.stringify(window.YataEditor?.getContent() ?? null)',
          )
          .timeout(const Duration(milliseconds: 150));
      Object? decoded = raw;
      if (decoded is String) {
        decoded = jsonDecode(decoded);
      }
      if (decoded is String) {
        decoded = jsonDecode(decoded);
      }
      if (decoded is Map) {
        final html = decoded['html'] as String?;
        if (html != null && html != _initialHtml) {
          _hasEdited = true;
          _latestHtml = html;
        }
      }
    } catch (_) {
      // Fall back to the latest debounced bridge update if JS evaluation is
      // unsupported or times out.
    }
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

  Future<void> _closeEditor() async {
    if (_closing || !mounted) return;
    _closing = true;
    await _pullLatestContentFromWebView();
    _flushSave();
    final controller = _webController;
    if (controller != null) {
      if (mounted) {
        setState(() => _webController = null);
      } else {
        _webController = null;
      }
      unawaited(controller.platform.closeWebViewSession().catchError((_) {}));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final controller = _webController;
    final showWebView = controller != null && !_closing;
    final transparentHole = !kIsWeb && Platform.isLinux && showWebView;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_closeEditor());
      },
      child: Scaffold(
        backgroundColor: transparentHole ? Colors.transparent : null,
        appBar: AppBar(
          leading: BackButton(onPressed: () => unawaited(_closeEditor())),
          title: Text(
            widget.task.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: showWebView
                  ? WebViewWidget(controller: controller)
                  : _plainController != null
                  ? Padding(
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
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),
            if (showWebView)
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeColor = theme.colorScheme.primary;
    final inactiveColor = theme.colorScheme.onSurfaceVariant;

    Widget formatButton({
      IconData? icon,
      Widget? iconWidget,
      required String tooltip,
      required bool active,
      VoidCallback? onPressed,
    }) {
      final color = active ? activeColor : inactiveColor;
      return IconButton(
        icon: iconWidget ?? Icon(icon, size: 20),
        tooltip: tooltip,
        color: color,
        style: active
            ? IconButton.styleFrom(
                backgroundColor: activeColor.withValues(alpha: 0.12),
              )
            : null,
        onPressed: onPressed,
      );
    }

    Widget textIcon(String label, bool active) {
      return Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: active ? activeColor : inactiveColor,
        ),
      );
    }

    return ExcludeFocus(
      child: Material(
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
                  formatButton(
                    iconWidget: textIcon('H1', state.headingLevel == 1),
                    tooltip: 'Title',
                    active: state.headingLevel == 1,
                    onPressed: () => onExec('heading1'),
                  ),
                  formatButton(
                    iconWidget: textIcon('H2', state.headingLevel == 2),
                    tooltip: 'Subhead',
                    active: state.headingLevel == 2,
                    onPressed: () => onExec('heading2'),
                  ),
                  formatButton(
                    icon: Icons.text_fields,
                    tooltip: 'Body',
                    active: state.headingLevel == 0,
                    onPressed: () => onExec('paragraph'),
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
      ),
    );
  }
}
