import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_all/webview_all.dart';

import '../../l10n/app_localizations.dart';
import '../../models/task_item.dart';
import '../../theme/todo_theme.dart';
import '../../ui/widgets/task_pickers.dart';
import 'note_editor_screen.dart';

/// Read-only note preview card matching `detailview/note/NoteCardView`.
///
/// Renders HTML notes in a bounded read-only WebView when available (falling back
/// to plain text otherwise) and opens [NoteEditorScreen] on tap.
class NoteCardView extends StatefulWidget {
  const NoteCardView({
    super.key,
    required this.task,
    required this.cardColor,
    required this.onNoteChanged,
    this.onRichNoteChanged,
  });

  final TaskItem task;
  final Color cardColor;
  final ValueChanged<String> onNoteChanged;
  final RichNoteChangedCallback? onRichNoteChanged;

  @override
  State<NoteCardView> createState() => _NoteCardViewState();
}

class _NoteCardViewState extends State<NoteCardView> {
  WebViewController? _previewController;
  bool _previewReady = false;
  String? _loadedTaskId;
  String? _loadedHtml;
  double _previewHeight = 84;

  bool get _shouldUseHtmlPreview =>
      isRichEditorWebViewSupported &&
      widget.task.isHtmlNote &&
      widget.task.noteHtml.trim().isNotEmpty;

  @override
  void didUpdateWidget(covariant NoteCardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_shouldUseHtmlPreview) return;
    if (_loadedTaskId != widget.task.id ||
        _loadedHtml != widget.task.noteHtml) {
      _syncPreviewContent();
    }
  }

  Future<void> _ensurePreviewController() async {
    if (_previewController != null) return;
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'YataBridge',
        onMessageReceived: (msg) => _handlePreviewMessage(msg.message),
      );
    _previewController = controller;
    try {
      final htmlAsset = await rootBundle.loadString('assets/editor/index.html');
      if (!mounted) return;
      await controller.loadHtmlString(htmlAsset);
    } catch (_) {
      if (!mounted) return;
      setState(() => _previewController = null);
    }
  }

  void _handlePreviewMessage(String raw) {
    if (!mounted) return;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return;

    switch (decoded['type']) {
      case 'ready':
        _previewReady = true;
        _syncPreviewContent();
      case 'heightChanged':
        final h = (decoded['height'] as num?)?.toDouble();
        if (h != null && h > 0) {
          final clamped = h.clamp(60.0, 142.0);
          if ((clamped - _previewHeight).abs() > 1) {
            setState(() => _previewHeight = clamped);
          }
        }
      case 'linkTap':
        final url = decoded['url'] as String?;
        if (url != null && url.isNotEmpty) {
          final uri = Uri.tryParse(url);
          if (uri != null) {
            launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        }
      case 'tapEmpty':
        _openEditor();
    }
  }

  void _syncPreviewContent() {
    final controller = _previewController;
    if (controller == null || !_previewReady || !mounted) return;
    _loadedTaskId = widget.task.id;
    _loadedHtml = widget.task.noteHtml;

    final theme = Theme.of(context);
    final payload = jsonEncode({
      'html': widget.task.noteHtml,
      'editable': false,
      'theme': {
        'bg': 'transparent',
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

  void _saveNote(String plainText, String html, String contentType) {
    final richCallback = widget.onRichNoteChanged;
    if (richCallback != null) {
      richCallback(plainText, html, contentType);
    } else {
      widget.onNoteChanged(plainText);
    }
  }

  void _openEditor() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            NoteEditorScreen(task: widget.task, onNoteSaved: _saveNote),
      ),
    );
  }

  void _showNoteMenu() {
    if (!widget.task.hasNote) return;
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: Text(l10n.copyTasks),
              onTap: () {
                Clipboard.setData(ClipboardData(text: widget.task.note));
                Navigator.of(sheetContext).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(l10n.delete),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _saveNote('', '', widget.task.noteContentType ?? 'Text');
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_shouldUseHtmlPreview) {
      _ensurePreviewController();
    }

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondaryText = isDark
        ? TodoColors.secondaryTextDark
        : TodoColors.secondaryTextLight;
    final hasVisibleNote = widget.task.hasNote;

    return Card(
      color: widget.cardColor,
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _openEditor,
        onLongPress: hasVisibleNote ? _showNoteMenu : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: double.infinity,
            minHeight: 132,
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (_shouldUseHtmlPreview && _previewController != null)
                  SizedBox(
                    height: _previewHeight,
                    child: WebViewWidget(controller: _previewController!),
                  )
                else
                  Text(
                    hasVisibleNote ? widget.task.note : l10n.addNotePlaceholder,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: hasVisibleNote ? null : secondaryText,
                    ),
                  ),
                if (hasVisibleNote && widget.task.noteUpdatedAt != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    formatNoteUpdatedDateLabel(
                      context,
                      widget.task.noteUpdatedAt!,
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: secondaryText,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
