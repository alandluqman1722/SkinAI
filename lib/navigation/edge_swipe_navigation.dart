import 'package:flutter/material.dart';

class EdgeSwipeNavigation extends StatefulWidget {
  const EdgeSwipeNavigation({
    required this.child,
    this.onBack,
    this.onForward,
    this.canGoBack,
    this.canStartAt,
    this.enabled = true,
    super.key,
  });

  final Widget child;
  final VoidCallback? onBack;
  final VoidCallback? onForward;
  final bool Function()? canGoBack;
  final bool Function(Offset position)? canStartAt;
  final bool enabled;

  @override
  State<EdgeSwipeNavigation> createState() => _EdgeSwipeNavigationState();
}

class _EdgeSwipeNavigationState extends State<EdgeSwipeNavigation>
    with SingleTickerProviderStateMixin {
  static const double _edgeWidth = 28;
  static const double _minimumSwipeDistance = 76;
  static const double _minimumFlingDistance = 36;
  static const double _minimumFlingVelocity = 700;
  static const Duration _settleDuration = Duration(milliseconds: 280);

  late final AnimationController _settleController;
  int? _activePointer;
  Offset? _startPosition;
  Duration? _startTime;
  double _dragOffset = 0;
  double _settleStartOffset = 0;
  bool _isSettling = false;

  @override
  void initState() {
    super.initState();
    _settleController = AnimationController(
      vsync: this,
      duration: _settleDuration,
    )..addStatusListener(_onSettleStatusChanged);
  }

  @override
  void dispose() {
    _settleController
      ..removeStatusListener(_onSettleStatusChanged)
      ..dispose();
    super.dispose();
  }

  void _onSettleStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      setState(() {
        _dragOffset = 0;
        _isSettling = false;
      });
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    final canStartAt = widget.canStartAt;
    if (!widget.enabled ||
        _activePointer != null ||
        _isSettling ||
        (widget.onBack == null && widget.onForward == null) ||
        _isTextFieldFocused ||
        (canStartAt != null && !canStartAt(event.position)) ||
        !_startsAtEdge(event.position.dx)) {
      return;
    }

    _activePointer = event.pointer;
    _startPosition = event.position;
    _startTime = event.timeStamp;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    if (_isTextFieldFocused) {
      _clearPointer();
      _settleDrag();
      return;
    }

    final delta = event.position - _startPosition!;
    if (delta.dy.abs() > delta.dx.abs() * 1.3 && delta.dy.abs() > 8) {
      _clearPointer();
      _settleDrag();
      return;
    }
    if (delta.dx.abs() < 4 ||
        delta.dx.abs() <= delta.dy.abs() * 1.3 ||
        _actionFor(delta.dx, Directionality.of(context)) == null) {
      return;
    }

    final width = MediaQuery.sizeOf(context).width;
    setState(() {
      _isSettling = false;
      _dragOffset = delta.dx.clamp(-width * 0.45, width * 0.45).toDouble();
    });
  }

  bool _startsAtEdge(double x) {
    final width = MediaQuery.sizeOf(context).width;
    return x <= _edgeWidth || x >= width - _edgeWidth;
  }

  bool get _isTextFieldFocused {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    return focusContext?.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  void _onPointerUp(PointerUpEvent event, TextDirection textDirection) {
    if (event.pointer != _activePointer) return;

    final start = _startPosition!;
    final end = event.position;
    final elapsed = event.timeStamp - _startTime!;
    final delta = end - start;
    final horizontalDistance = delta.dx.abs();
    final verticalDistance = delta.dy.abs();
    final velocity = elapsed.inMicroseconds == 0
        ? 0.0
        : horizontalDistance *
            Duration.microsecondsPerSecond /
            elapsed.inMicroseconds;
    final isHorizontal = horizontalDistance > verticalDistance * 1.3;
    final hasEnoughDistance = horizontalDistance >= _minimumSwipeDistance ||
        (horizontalDistance >= _minimumFlingDistance &&
            velocity >= _minimumFlingVelocity);
    final action = _actionFor(delta.dx, textDirection);
    _clearPointer();
    if (action != null &&
        widget.enabled &&
        !_isTextFieldFocused &&
        isHorizontal &&
        hasEnoughDistance) {
      action();
    }
    _settleDrag();
  }

  VoidCallback? _actionFor(
      double horizontalDelta, TextDirection textDirection) {
    if (_startPosition == null || horizontalDelta == 0) return null;

    final width = MediaQuery.sizeOf(context).width;
    final startsAtLeft = _startPosition!.dx <= _edgeWidth;
    final startsAtRight = _startPosition!.dx >= width - _edgeWidth;
    final movesInward = (startsAtLeft && horizontalDelta > 0) ||
        (startsAtRight && horizontalDelta < 0);
    if (!movesInward) return null;

    final isNextSection = textDirection == TextDirection.ltr
        ? horizontalDelta < 0
        : horizontalDelta > 0;
    if (isNextSection) return widget.onForward;
    final canGoBack = widget.canGoBack;
    if (canGoBack != null && !canGoBack()) return null;
    return widget.onBack;
  }

  void _settleDrag() {
    if (_dragOffset.abs() < 1) return;
    _settleStartOffset = _dragOffset;
    _isSettling = true;
    _settleController.forward(from: 0);
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer == _activePointer) {
      _clearPointer();
      _settleDrag();
    }
  }

  void _clearPointer() {
    _activePointer = null;
    _startPosition = null;
    _startTime = null;
  }

  @override
  Widget build(BuildContext context) {
    final textDirection = Directionality.of(context);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: (event) => _onPointerUp(event, textDirection),
      onPointerCancel: _onPointerCancel,
      child: AnimatedBuilder(
        animation: _settleController,
        child: widget.child,
        builder: (context, child) {
          final offset = _isSettling
              ? _settleStartOffset *
                  (1 - Curves.easeOutCubic.transform(_settleController.value))
              : _dragOffset;
          return ClipRect(
            child: ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: Transform.translate(
                offset: Offset(offset, 0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    boxShadow: offset == 0
                        ? null
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.22),
                              blurRadius: 20,
                              spreadRadius: 1,
                            ),
                          ],
                  ),
                  child: child,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
