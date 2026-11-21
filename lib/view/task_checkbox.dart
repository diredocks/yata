import 'package:lottie/lottie.dart';
import 'package:material_ui/material_ui.dart';
import '../theme/todo_theme.dart';

class TaskCheckbox extends StatefulWidget {
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
  State<TaskCheckbox> createState() => _TaskCheckboxState();
}

class _TaskCheckboxState extends State<TaskCheckbox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _confettiController;
  bool _showConfetti = false;

  @override
  void initState() {
    super.initState();
    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _showConfetti = false);
        }
      });
  }

  @override
  void didUpdateWidget(covariant TaskCheckbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isChecked && widget.isChecked) {
      setState(() => _showConfetti = true);
      _confettiController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = widget.accentColor ??
        (isDark ? TodoColors.attentionDark : TodoColors.attentionLight);
    final borderColor = widget.isChecked
        ? activeColor
        : (isDark
            ? TodoColors.secondaryTextDark
            : TodoColors.secondaryTextLight);

    return InkResponse(
      onTap: widget.onTap,
      radius: 20,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            if (_showConfetti)
              SizedBox(
                width: widget.size,
                height: widget.size,
                child: OverflowBox(
                  maxWidth: widget.size * 2.4,
                  maxHeight: widget.size * 2.4,
                  child: IgnorePointer(
                    child: Lottie.asset(
                      'assets/animations/confetti.json',
                      controller: _confettiController,
                      repeat: false,
                      onLoaded: (composition) {
                        _confettiController.duration = composition.duration;
                      },
                    ),
                  ),
                ),
              ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.isChecked ? activeColor : Colors.transparent,
                border: Border.all(color: borderColor, width: 1.8),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                switchInCurve: Curves.easeOutBack,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: widget.isChecked
                    ? Icon(
                        Icons.check,
                        key: const ValueKey('checked'),
                        size: widget.size * 0.65,
                        color: Colors.white,
                      )
                    : const SizedBox.shrink(key: ValueKey('unchecked')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
