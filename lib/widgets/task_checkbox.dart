import 'package:material_ui/material_ui.dart';
import '../theme/todo_theme.dart';

class TaskCheckbox extends StatelessWidget {
  const TaskCheckbox({
    super.key,
    required this.isChecked,
    required this.onTap,
    this.accentColor,
    this.size = 22,
  });

  final bool isChecked;
  final VoidCallback onTap;
  final Color? accentColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = accentColor ??
        (isDark ? TodoColors.attentionDark : TodoColors.attentionLight);
    final borderColor = isChecked
        ? activeColor
        : (isDark
            ? TodoColors.secondaryTextDark
            : TodoColors.secondaryTextLight);

    return InkResponse(
      onTap: onTap,
      radius: 20,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isChecked ? activeColor : Colors.transparent,
            border: Border.all(color: borderColor, width: 1.8),
          ),
          child: isChecked
              ? Icon(
                  Icons.check,
                  size: size * 0.65,
                  color: Colors.white,
                )
              : null,
        ),
      ),
    );
  }
}
