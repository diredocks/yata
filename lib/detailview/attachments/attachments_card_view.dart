import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/task_item.dart';
import '../../theme/todo_theme.dart';
import '../details/detail_cards.dart';
import 'attachment_format.dart';

enum AttachmentSourceChoice { camera, file }

/// Bottom sheet matching `FileUploadBottomSheet` (`ai/z.java`) with Camera
/// and File Picker options.
Future<AttachmentSourceChoice?> showAttachmentSourceSheet(
  BuildContext context,
) {
  final l10n = AppLocalizations.of(context);
  return showModalBottomSheet<AttachmentSourceChoice>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(l10n.takePhoto),
            onTap: () => Navigator.pop(ctx, AttachmentSourceChoice.camera),
          ),
          ListTile(
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: Text(l10n.chooseFile),
            onTap: () => Navigator.pop(ctx, AttachmentSourceChoice.file),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Attachments card matching `detailview/linked entity` (`FileViewHolder` and
/// `AddFileViewHolder`).
class AttachmentsCardView extends StatelessWidget {
  const AttachmentsCardView({
    super.key,
    required this.task,
    required this.cardColor,
    required this.onAddAttachment,
    required this.onTapAttachment,
    required this.onDeleteAttachment,
    this.accentColor,
  });

  final TaskItem task;
  final Color cardColor;
  final VoidCallback onAddAttachment;
  final ValueChanged<TaskAttachment> onTapAttachment;
  final ValueChanged<TaskAttachment> onDeleteAttachment;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryText = isDark
        ? TodoColors.secondaryTextDark
        : TodoColors.secondaryTextLight;
    final accent =
        accentColor ??
        (isDark ? TodoColors.attentionDark : TodoColors.attentionLight);

    return Card(
      color: cardColor,
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: [
          for (final attachment in task.attachments) ...[
            _AttachmentRow(
              attachment: attachment,
              accentColor: accent,
              secondaryText: secondaryText,
              onTap: () => onTapAttachment(attachment),
              onDelete: attachment.isTransferring && attachment.remoteId == null
                  ? null
                  : () => onDeleteAttachment(attachment),
            ),
            const Divider(height: 1, indent: 64),
          ],
          DetailActionRow(
            icon: Icons.attach_file,
            iconColor: secondaryText,
            label: l10n.addFile,
            labelColor: secondaryText,
            removeColor: secondaryText,
            onTap: onAddAttachment,
          ),
        ],
      ),
    );
  }
}

class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({
    required this.attachment,
    required this.accentColor,
    required this.secondaryText,
    required this.onTap,
    required this.onDelete,
  });

  final TaskAttachment attachment;
  final Color accentColor;
  final Color secondaryText;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badge = attachment.badgeLabel;
    final sizeText = attachment.size > 0
        ? formatFileSize(attachment.size)
        : null;
    final subtitleParts = [?sizeText, ?badge];
    final subtitle = subtitleParts.join(' · ');

    return InkWell(
      onTap: attachment.isTransferring ? null : onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Row(
          children: [
            const SizedBox(width: 12),
            _AttachmentLeadingBadge(
              attachment: attachment,
              accentColor: accentColor,
              secondaryText: secondaryText,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      attachment.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: secondaryText,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (onDelete != null)
              InkWell(
                onTap: onDelete,
                borderRadius: BorderRadius.circular(24),
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: 16,
                    end: 14,
                    top: 13,
                    bottom: 13,
                  ),
                  child: Icon(Icons.close, size: 22, color: secondaryText),
                ),
              )
            else
              const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }
}

class _AttachmentLeadingBadge extends StatelessWidget {
  const _AttachmentLeadingBadge({
    required this.attachment,
    required this.accentColor,
    required this.secondaryText,
  });

  final TaskAttachment attachment;
  final Color accentColor;
  final Color secondaryText;

  @override
  Widget build(BuildContext context) {
    final badge = attachment.badgeLabel;
    final hasLocalFile =
        attachment.localPath != null && attachment.localPath!.isNotEmpty;

    Widget content;
    if (attachment.isTransferring) {
      content = SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: accentColor),
      );
    } else if (attachment.isLinkOnly) {
      content = Icon(Icons.open_in_new, size: 20, color: accentColor);
    } else if (!hasLocalFile) {
      content = Icon(Icons.download_outlined, size: 20, color: accentColor);
    } else if (badge != null) {
      content = Text(
        badge,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: accentColor,
        ),
      );
    } else {
      content = Icon(
        Icons.insert_drive_file_outlined,
        size: 20,
        color: secondaryText,
      );
    }

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: content,
    );
  }
}
