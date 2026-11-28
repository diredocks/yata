import 'dart:async';

import 'package:material_ui/material_ui.dart';

const _toastVisibleDuration = Duration(seconds: 4);
const _toastAnimationDuration = Duration(milliseconds: 180);

OverlayEntry? _activeToastEntry;

void _dismissToast(OverlayEntry entry) {
  if (identical(_activeToastEntry, entry)) _activeToastEntry = null;
  if (!entry.mounted) return;
  entry.remove();
  entry.dispose();
}

/// Shows a transient toast in the root overlay so it survives the route that
/// triggered it being popped.
void showAppToast(BuildContext context, String message) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  final previous = _activeToastEntry;
  if (previous != null) _dismissToast(previous);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) =>
        _AppToast(message: message, onDismissed: () => _dismissToast(entry)),
  );
  _activeToastEntry = entry;
  overlay.insert(entry);
}

class _AppToast extends StatefulWidget {
  const _AppToast({required this.message, required this.onDismissed});

  final String message;
  final VoidCallback onDismissed;

  @override
  State<_AppToast> createState() => _AppToastState();
}

class _AppToastState extends State<_AppToast> {
  Timer? _dismissTimer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _visible = true);
      _dismissTimer = Timer(_toastVisibleDuration, () {
        if (!mounted) return;
        setState(() => _visible = false);
        _dismissTimer = Timer(_toastAnimationDuration, widget.onDismissed);
      });
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion ? Duration.zero : _toastAnimationDuration;
    return Positioned(
      left: 16,
      right: 16,
      bottom: MediaQuery.viewPaddingOf(context).bottom + 24,
      child: IgnorePointer(
        child: AnimatedSlide(
          offset: _visible ? Offset.zero : const Offset(0, 0.3),
          duration: duration,
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: duration,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Material(
                  color: theme.colorScheme.inverseSurface,
                  elevation: 6,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Text(
                      widget.message,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onInverseSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
