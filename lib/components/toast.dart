import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lnu_elytra/utils/state.dart';

/// Visual flavour of a toast, mapped to colour + icon in [_ToastItem].
enum ToastType { info, success, error }

/// One live toast's data: an id (for keying + removal), its text, flavour, and
/// how long it stays before auto-dismissing.
class ToastData {
  ToastData(this.id, this.message, this.type, this.duration);

  final int id;
  final String message;
  final ToastType type;
  final Duration duration;
}

/// A queue-free toast notifier.
///
/// Unlike [ScaffoldMessenger], which shows one snackbar at a time and makes
/// every new one wait for the current to dismiss, toasts here appear
/// immediately and *stack*. That suits rapid grab feedback, where a burst of
/// results would otherwise back up behind a 4-second queue.
///
/// Every toast is also mirrored to [logStore] at the matching level —
/// info/success → INFO, error → ERROR — so user-facing alerts are never lost
/// from the log even after the toast itself fades.
///
/// Drive it from anywhere via the [toaster] singleton; [ToastOverlay] (mounted
/// once in `MyApp`) renders whatever it holds. No [BuildContext] needed at the
/// call site.
class Toaster extends ChangeNotifier {
  final List<ToastData> _toasts = [];
  int _seq = 0;

  /// Cap on simultaneously-live toasts; the oldest is dropped past this so a
  /// flood can't fill the screen.
  static const int maxVisible = 4;

  static const Duration _defaultDuration = Duration(milliseconds: 1800);
  static const Duration _errorDuration = Duration(milliseconds: 2800);

  List<ToastData> get toasts => List.unmodifiable(_toasts);

  /// Show a toast. Returns immediately; never blocks or queues.
  /// Also writes to [logStore] at the matching level.
  void show(
    String message, {
    ToastType type = ToastType.info,
    Duration? duration,
  }) {
    // Mirror to the log so user-facing alerts survive in history.
    switch (type) {
      case ToastType.error:
        logStore.error(message, target: 'toast');
      case ToastType.success:
      case ToastType.info:
        logStore.info(message, target: 'toast');
    }
    _toasts.add(ToastData(_seq++, message, type, duration ?? _defaultDuration));
    if (_toasts.length > maxVisible) _toasts.removeAt(0);
    notifyListeners();
  }

  void info(String message) => show(message);
  void success(String message) => show(message, type: ToastType.success);
  void error(String message) =>
      show(message, type: ToastType.error, duration: _errorDuration);

  /// Called by a [_ToastItem] once its exit animation has finished, so the
  /// item is already invisible by the time its data leaves the list.
  void _remove(int id) {
    _toasts.removeWhere((t) => t.id == id);
    notifyListeners();
  }
}

/// Global toast singleton, mirroring [session] / [logStore].
final toaster = Toaster();

/// Floating toast layer. Mount once near the top of the tree (see `MyApp`); it
/// listens to [toaster] and stacks toasts below the top edge, above all routes
/// and dialogs.
class ToastOverlay extends StatelessWidget {
  const ToastOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: AnimatedBuilder(
                animation: toaster,
                builder: (context, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final t in toaster.toasts)
                      _ToastItem(key: ValueKey(t.id), data: t),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A single toast. Owns its lifecycle: animates in on mount, auto-dismisses
/// after [ToastData.duration], and removes its own data only once the exit
/// animation completes — so the column reflows smoothly as it shrinks away.
class _ToastItem extends StatefulWidget {
  const _ToastItem({super.key, required this.data});

  final ToastData data;

  @override
  State<_ToastItem> createState() => _ToastItemState();
}

class _ToastItemState extends State<_ToastItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    // Snappy in/out — well short of the old snackbar's leisurely slide.
    duration: const Duration(milliseconds: 180),
  );
  Timer? _timer;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
    _timer = Timer(widget.data.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (_leaving) return;
    _leaving = true;
    _timer?.cancel();
    if (mounted) await _ctrl.reverse();
    toaster._remove(widget.data.id);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    return SizeTransition(
      sizeFactor: curve,
      child: FadeTransition(
        opacity: curve,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, -0.25),
            end: Offset.zero,
          ).animate(curve),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _bubble(context),
          ),
        ),
      ),
    );
  }

  Widget _bubble(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color bg, Color fg, IconData icon) = switch (widget.data.type) {
      ToastType.success => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        Icons.check_circle_outline,
      ),
      ToastType.error => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.error_outline,
      ),
      ToastType.info => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
        Icons.info_outline,
      ),
    };
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Material(
          color: bg,
          elevation: 3,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            // Tap anywhere to dismiss early.
            onTap: _dismiss,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: fg),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      widget.data.message,
                      style: TextStyle(color: fg, fontSize: 13.5),
                    ),
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
