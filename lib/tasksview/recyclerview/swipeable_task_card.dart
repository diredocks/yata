import 'package:material_ui/material_ui.dart';
import '../../theme/todo_theme.dart';

/// Swipe-to-action wrapper matching `ep/a2.java` (`TouchHelperTaskViewItemCallback`)
/// and `ep/o0.java` (`SwipeBackgroundHelper`):
/// - Swipe right (`dx > 0`): toggle "My Day" with `item_swiped` (`#29000000`) base
///   and an expanding circular reveal in `accentColor` once past the 40% threshold.
/// - Swipe left (`dx < 0`): delete task with `item_swiped` base and an expanding
///   circular reveal in `TodoColors.overdueRed` once past the 40% threshold.
class SwipeableTaskCard extends StatefulWidget {
  const SwipeableTaskCard({
    super.key,
    required this.enabled,
    required this.isInMyDay,
    required this.accentColor,
    required this.onSwipeRight,
    required this.onSwipeLeft,
    required this.child,
  });

  final bool enabled;
  final bool isInMyDay;
  final Color accentColor;
  final VoidCallback onSwipeRight;
  final VoidCallback onSwipeLeft;
  final Widget child;

  @override
  State<SwipeableTaskCard> createState() => _SwipeableTaskCardState();
}

enum _SwipeAnimPhase {
  idle,
  flingRight,
  flingLeft,
  snapBack,
}

class _SwipeableTaskCardState extends State<SwipeableTaskCard>
    with SingleTickerProviderStateMixin {
  static const double _swipeThreshold = 0.4;
  static const double _circleGrowthFactor = 3.0;
  static const Color _itemSwipedColor = Color(0x29000000);
  static const Duration _flingDuration = Duration(milliseconds: 180);
  static const Duration _snapBackDuration = Duration(milliseconds: 220);

  late final AnimationController _snapController;
  Animation<double>? _snapAnimation;
  double _dragOffset = 0.0;
  _SwipeAnimPhase _phase = _SwipeAnimPhase.idle;

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController(
      vsync: this,
      duration: _snapBackDuration,
    )
      ..addListener(() {
        if (_snapAnimation != null && mounted) {
          setState(() => _dragOffset = _snapAnimation!.value);
        }
      })
      ..addStatusListener((status) {
        if (status != AnimationStatus.completed || !mounted) return;
        final completedPhase = _phase;
        _phase = _SwipeAnimPhase.idle;
        if (completedPhase == _SwipeAnimPhase.flingRight) {
          widget.onSwipeRight();
          if (mounted) {
            _animateBack();
          }
        } else if (completedPhase == _SwipeAnimPhase.flingLeft) {
          widget.onSwipeLeft();
        }
      });
  }

  @override
  void didUpdateWidget(covariant SwipeableTaskCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled &&
        (_dragOffset != 0.0 || _phase != _SwipeAnimPhase.idle)) {
      _phase = _SwipeAnimPhase.idle;
      _snapController.stop();
      _dragOffset = 0.0;
    }
  }

  @override
  void dispose() {
    _snapController.dispose();
    super.dispose();
  }

  void _animateTo(
    double target, {
    required _SwipeAnimPhase phase,
    required Duration duration,
  }) {
    _phase = phase;
    _snapController.duration = duration;
    _snapAnimation = Tween<double>(begin: _dragOffset, end: target).animate(
      CurvedAnimation(parent: _snapController, curve: Curves.easeOutCubic),
    );
    _snapController.forward(from: 0);
  }

  void _animateBack() {
    _animateTo(
      0.0,
      phase: _SwipeAnimPhase.snapBack,
      duration: _snapBackDuration,
    );
  }

  void _handleDragStart(DragStartDetails details) {
    if (!widget.enabled) return;
    _phase = _SwipeAnimPhase.idle;
    _snapController.stop();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!widget.enabled) return;
    setState(() {
      _dragOffset += details.delta.dx;
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    if (!widget.enabled) return;
    final width = context.size?.width ?? 1.0;
    final ratio = (_dragOffset / width).abs();
    final velocity = details.primaryVelocity ?? 0.0;
    final triggered = ratio >= _swipeThreshold ||
        (velocity.abs() > 700 && ratio > 0.15);

    if (triggered) {
      final isRight = _dragOffset > 0;
      _animateTo(
        isRight ? width : -width,
        phase: isRight ? _SwipeAnimPhase.flingRight : _SwipeAnimPhase.flingLeft,
        duration: _flingDuration,
      );
    } else {
      _animateBack();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }

    final isSwipingRight = _dragOffset > 0;
    final isSwiping = _dragOffset.abs() > 0.5;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: _handleDragStart,
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd: _handleDragEnd,
      onHorizontalDragCancel: _animateBack,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (isSwiping)
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final progress = (_dragOffset.abs() / width).clamp(0.0, 1.0);
                    final revealColor = isSwipingRight
                        ? widget.accentColor
                        : TodoColors.overdueRed;
                    final icon = isSwipingRight
                        ? (widget.isInMyDay
                            ? Icons.wb_sunny
                            : Icons.wb_sunny_outlined)
                        : Icons.delete_outline;

                    return CustomPaint(
                      painter: _SwipeBackgroundPainter(
                        dragOffset: _dragOffset,
                        progress: progress,
                        threshold: _swipeThreshold,
                        growthFactor: _circleGrowthFactor,
                        baseColor: _itemSwipedColor,
                        revealColor: revealColor,
                      ),
                      child: Align(
                        alignment: isSwipingRight
                            ? Alignment.centerLeft
                            : Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Icon(
                            icon,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          Transform.translate(
            offset: Offset(_dragOffset, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

class _SwipeBackgroundPainter extends CustomPainter {
  _SwipeBackgroundPainter({
    required this.dragOffset,
    required this.progress,
    required this.threshold,
    required this.growthFactor,
    required this.baseColor,
    required this.revealColor,
  });

  final double dragOffset;
  final double progress;
  final double threshold;
  final double growthFactor;
  final Color baseColor;
  final Color revealColor;

  @override
  void paint(Canvas canvas, Size size) {
    final isRight = dragOffset > 0;
    final rect = isRight
        ? Rect.fromLTWH(0, 0, (dragOffset + 8).clamp(0.0, size.width), size.height)
        : Rect.fromLTWH(
            (size.width + dragOffset - 8).clamp(0.0, size.width),
            0,
            (-dragOffset + 8).clamp(0.0, size.width),
            size.height,
          );

    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawColor(baseColor, BlendMode.srcOver);

    final circleRadius = (progress - threshold) * size.width * growthFactor;
    if (circleRadius > 0) {
      final centerX = isRight ? 31.0 : size.width - 31.0;
      final centerY = size.height / 2;
      final paint = Paint()
        ..color = revealColor
        ..isAntiAlias = true;
      canvas.drawCircle(Offset(centerX, centerY), circleRadius, paint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SwipeBackgroundPainter oldDelegate) {
    return oldDelegate.dragOffset != dragOffset ||
        oldDelegate.revealColor != revealColor ||
        oldDelegate.baseColor != baseColor;
  }
}
