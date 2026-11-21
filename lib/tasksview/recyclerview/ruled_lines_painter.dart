import 'package:material_ui/material_ui.dart';

/// Ruled background lines painter for `tasksview/TasksViewFragment`.
class RuledLinesPainter extends CustomPainter {
  const RuledLinesPainter({
    required this.lineColor,
    required this.rowHeight,
    required this.horizontalInset,
  });

  final Color lineColor;
  final double rowHeight;
  final double horizontalInset;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.0;

    for (var y = rowHeight; y < size.height; y += rowHeight) {
      canvas.drawLine(
        Offset(horizontalInset, y),
        Offset(size.width - horizontalInset, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant RuledLinesPainter oldDelegate) {
    return oldDelegate.lineColor != lineColor ||
        oldDelegate.rowHeight != rowHeight ||
        oldDelegate.horizontalInset != horizontalInset;
  }
}
