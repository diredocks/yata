import 'package:material_ui/material_ui.dart';
import '../../theme/todo_theme.dart';

/// List row item in `homeview/HomeViewFragment`.
class HomeListTile extends StatelessWidget {
  const HomeListTile({
    super.key,
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.count,
    required this.onTap,
    this.emoji,
    this.isSelected = false,
    this.isGrouped = false,
  });

  final String title;
  final String? emoji;
  final IconData icon;
  final Color iconColor;
  final int count;
  final VoidCallback onTap;
  final bool isSelected;
  final bool isGrouped;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final selectedBg = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : TodoColors.blue100.withValues(alpha: 0.08);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Material(
        color: isSelected ? selectedBg : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            constraints: const BoxConstraints(minHeight: 46),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                if (isGrouped) ...[
                  Container(
                    width: 2,
                    height: 20,
                    margin: const EdgeInsets.only(left: 4, right: 12),
                    color: theme.dividerColor,
                  ),
                ],
                if (emoji != null && emoji!.isNotEmpty)
                  SizedBox(
                    width: 22,
                    child: Center(
                      child: Text(emoji!, style: const TextStyle(fontSize: 18)),
                    ),
                  )
                else
                  Icon(icon, size: 22, color: iconColor),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: 15,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (count > 0)
                  Text(
                    '$count',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isDark
                          ? TodoColors.secondaryTextDark
                          : TodoColors.secondaryTextLight,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
