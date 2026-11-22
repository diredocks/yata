import 'package:lottie/lottie.dart';
import 'package:material_ui/material_ui.dart';
import '../theme/todo_theme.dart';

/// Mode matching `AnimatableCheckBox.b` (`COMPLETE` vs `SELECT`).
enum CheckboxMode {
  complete,
  select,
}

/// Task/step completion checkbox matching `AnimatableCheckBox.java`:
/// - Unchecked: hollow circle (`emptyCircle`), checkmark hidden at 1.8x scale.
/// - Checking: `emptyCircle` shrinks/fades out (200ms), `filledCircle` scales
///   in (50ms delay, 300ms), `checkmark` scales 1.8->1.0 & fades in (50ms delay,
///   300ms), and for tasks (`showConfetti: true` & `mode == CheckboxMode.complete`)
///   `confetti.json` plays at 5x speed.
/// - Unchecking: `emptyCircle` restores (10ms), `filledCircle` shrinks out
///   (100ms), `checkmark` scales 1.0->1.8 & fades out (20ms).
class TaskCheckbox extends StatefulWidget {
  const TaskCheckbox({
    super.key,
    required this.isChecked,
    required this.onTap,
    this.accentColor,
    this.size = 22,
    this.showConfetti = true,
    this.mode = CheckboxMode.complete,
  });

  final bool isChecked;
  final VoidCallback onTap;
  final Color? accentColor;
  final double size;
  final bool showConfetti;
  final CheckboxMode mode;

  @override
  State<TaskCheckbox> createState() => _TaskCheckboxState();
}

class _TaskCheckboxState extends State<TaskCheckbox>
    with TickerProviderStateMixin {
  static const _checkDuration = Duration(milliseconds: 350);
  static const _uncheckDuration = Duration(milliseconds: 100);
  static const _confettiDefaultDuration = Duration(milliseconds: 360);

  late final AnimationController _checkController;
  late final AnimationController _confettiController;
  bool _showConfetti = false;

  @override
  void initState() {
    super.initState();
    _checkController = AnimationController(
      vsync: this,
      duration: _checkDuration,
      reverseDuration: _uncheckDuration,
      value: widget.isChecked ? 1.0 : 0.0,
    );
    _confettiController = AnimationController(
      vsync: this,
      duration: _confettiDefaultDuration,
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
      _checkController.forward();
      if (widget.showConfetti && widget.mode == CheckboxMode.complete) {
        setState(() => _showConfetti = true);
        _confettiController.forward(from: 0);
      }
    } else if (oldWidget.isChecked && !widget.isChecked) {
      _checkController.reverse();
      if (_showConfetti) {
        _confettiController.stop();
        setState(() => _showConfetti = false);
      }
    }
  }

  @override
  void dispose() {
    _checkController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = widget.accentColor ??
        (isDark ? TodoColors.attentionDark : TodoColors.attentionLight);
    final uncheckedBorderColor = widget.mode == CheckboxMode.select
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
                        final target = composition.duration ~/ 5;
                        if (target > Duration.zero &&
                            _confettiController.duration != target) {
                          _confettiController.duration = target;
                        }
                      },
                    ),
                  ),
                ),
              ),
            SizedBox(
              width: widget.size,
              height: widget.size,
              child: AnimatedBuilder(
                animation: _checkController,
                builder: (context, _) {
                  final t = _checkController.value;
                  final isForward =
                      _checkController.status != AnimationStatus.reverse;

                  // Empty circle: 0..200ms out when checking, 0..10ms in when unchecking
                  final double emptyProgress;
                  if (isForward) {
                    emptyProgress =
                        1.0 - Curves.decelerate.transform((t / (200 / 350)).clamp(0.0, 1.0));
                  } else {
                    emptyProgress =
                        1.0 - Curves.decelerate.transform((t / 0.1).clamp(0.0, 1.0));
                  }

                  // Filled circle: 50..350ms in when checking, 0..100ms out when unchecking
                  final double filledProgress;
                  if (isForward) {
                    filledProgress = Curves.decelerate.transform(
                      ((t - (50 / 350)) / (300 / 350)).clamp(0.0, 1.0),
                    );
                  } else {
                    filledProgress = Curves.decelerate.transform(t);
                  }

                  // Checkmark: 50..350ms in (scale 1.8->1.0) when checking,
                  // 0..20ms out (scale 1.0->1.8) when unchecking
                  final double checkProgress;
                  if (isForward) {
                    checkProgress = filledProgress;
                  } else {
                    checkProgress = Curves.decelerate.transform(
                      ((t - 0.8) / 0.2).clamp(0.0, 1.0),
                    );
                  }
                  final checkScale = 1.8 - 0.8 * checkProgress;

                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      if (emptyProgress > 0.001)
                        Transform.scale(
                          scale: emptyProgress,
                          child: Opacity(
                            opacity: emptyProgress,
                            child: Container(
                              width: widget.size,
                              height: widget.size,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: uncheckedBorderColor,
                                  width: 1.8,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (filledProgress > 0.001)
                        Transform.scale(
                          scale: filledProgress,
                          child: Opacity(
                            opacity: filledProgress,
                            child: Container(
                              width: widget.size,
                              height: widget.size,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: activeColor,
                              ),
                            ),
                          ),
                        ),
                      if (widget.isChecked || checkProgress > 0.001)
                        Transform.scale(
                          scale: checkScale,
                          child: Opacity(
                            opacity: checkProgress,
                            child: Icon(
                              Icons.check,
                              key: const ValueKey('checked'),
                              size: widget.size * 0.65,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
