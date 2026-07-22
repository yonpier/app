import 'package:flutter/material.dart';
import 'package:vikunja_app/domain/entities/task.dart';

/// Result of a completed drag or resize action on a Gantt bar.
class GanttDragResult {
  final int taskId;
  final DateTime? newStartDate;
  final DateTime? newEndDate;

  GanttDragResult({
    required this.taskId,
    required this.newStartDate,
    required this.newEndDate,
  });
}

/// A single Gantt bar (both dates present) or marker (one date present).
///
/// Interactions:
/// - **Long press** + horizontal drag → move the whole bar (preserving duration).
/// - **Left / right handle** drag → resize only start / end date.
/// - **Tap** → calls [onTap].
class GanttTaskBar extends StatefulWidget {
  final Task task;
  final double dayWidth;
  final double taskHeight;
  final DateTime timelineStart;
  final int offsetDays;
  final int durationDays;
  final bool isBar;

  /// Callbacks — all nullable so the parent can wire only what it needs.
  final void Function(GanttDragResult result)? onDragEnd;
  /// [taskId] is passed for bar drags (to enable date computation in parent),
  /// omitted for resize handle drags.
  final void Function([int? taskId])? onAnyDragStarted;
  final VoidCallback? onAnyDragEnded;
  final void Function(Offset globalPos)? onAnyDragUpdate;
  final void Function(Task task)? onTap;

  const GanttTaskBar({
    super.key,
    required this.task,
    required this.dayWidth,
    required this.taskHeight,
    required this.timelineStart,
    required this.offsetDays,
    required this.durationDays,
    required this.isBar,
    this.onDragEnd,
    this.onAnyDragStarted,
    this.onAnyDragEnded,
    this.onAnyDragUpdate,
    this.onTap,
  });

  @override
  State<GanttTaskBar> createState() => _GanttTaskBarState();
}

class _GanttTaskBarState extends State<GanttTaskBar> {
  // Accumulated deltas for handle resizes.
  double _leftDelta = 0;
  double _rightDelta = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final barColor = widget.task.color ?? theme.colorScheme.primary;
    final textColor =
        barColor.computeLuminance() > 0.5 ? Colors.black : Colors.white;

    // ----- Build the inner content (bar or marker) -----
    Widget content;
    if (widget.isBar) {
      content = _buildBar(theme, barColor, textColor);
    } else {
      content = _buildMarker(barColor, textColor);
    }

    // Wrap content so taps always fire.
    Widget inner = GestureDetector(
      onTap: () => widget.onTap?.call(widget.task),
      child: content,
    );

    // For bars: use GestureDetector with long-press to allow moving.
    // Date computation is delegated to the parent via global position.
    if (widget.isBar) {
      inner = GestureDetector(
        onLongPressStart: (details) {
          widget.onAnyDragStarted?.call(widget.task.id);
        },
        onLongPressMoveUpdate: (details) {
          widget.onAnyDragUpdate?.call(details.globalPosition);
        },
        onLongPressEnd: (details) {
          widget.onAnyDragEnded?.call();
        },
        child: GestureDetector(
          onTap: () => widget.onTap?.call(widget.task),
          child: content,
        ),
      );
    }

    return inner;
  }

  // -----------------------------------------------------------------------
  // Bar rendering
  // -----------------------------------------------------------------------

  Widget _buildBar(ThemeData theme, Color barColor, Color textColor) {
    final baseWidth = widget.durationDays * widget.dayWidth;
    final totalWidth = baseWidth + _leftDelta + _rightDelta;
    final leftPad = _leftDelta < 0 ? _leftDelta.abs() : 0.0;
    final effectiveWidth = (totalWidth - leftPad).clamp(widget.dayWidth, double.infinity);

    return Container(
      height: widget.taskHeight * 0.7,
      width: effectiveWidth,
      margin: EdgeInsets.only(left: leftPad),
      decoration: BoxDecoration(
        color: barColor.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          _buildHandle(side: 'left', onUpdate: _onLeftHandleUpdate, onEnd: _commitLeftHandle),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                widget.task.title,
                style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ),
          _buildHandle(side: 'right', onUpdate: _onRightHandleUpdate, onEnd: _commitRightHandle),
        ],
      ),
    );
  }

  Widget _buildMarker(Color barColor, Color textColor) {
    return Container(
      width: widget.taskHeight * 0.5,
      height: widget.taskHeight * 0.5,
      margin: EdgeInsets.only(top: widget.taskHeight * 0.1),
      decoration: BoxDecoration(
        color: barColor,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        widget.task.hasStartDate ? '▶' : '◀',
        style: TextStyle(color: textColor, fontSize: 10),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Resize handles
  // -----------------------------------------------------------------------

  Widget _buildHandle({
    required String side,
    required void Function(DragUpdateDetails) onUpdate,
    required VoidCallback onEnd,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => widget.onAnyDragStarted?.call(),
      onPanUpdate: (d) {
        onUpdate(d);
        widget.onAnyDragUpdate?.call(d.globalPosition);
      },
      onPanEnd: (_) {
        onEnd();
        widget.onAnyDragEnded?.call();
      },
      child: Container(
        width: 12,
        color: Colors.transparent,
        child: Center(
          child: Container(
            width: 4,
            height: widget.taskHeight * 0.4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  void _onLeftHandleUpdate(DragUpdateDetails details) {
    setState(() => _leftDelta += details.delta.dx);
  }

  void _onRightHandleUpdate(DragUpdateDetails details) {
    setState(() => _rightDelta += details.delta.dx);
  }

  void _commitLeftHandle() {
    if (_leftDelta == 0) return;
    final days = (_leftDelta / widget.dayWidth).round();
    if (days == 0) return;
    final original = widget.task.startDate!;
    final updated = DateTime(original.year, original.month, original.day + days);
    widget.onDragEnd?.call(GanttDragResult(
      taskId: widget.task.id,
      newStartDate: updated,
      newEndDate: widget.task.endDate,
    ));
    _leftDelta = 0;
  }

  void _commitRightHandle() {
    if (_rightDelta == 0) return;
    final days = (_rightDelta / widget.dayWidth).round();
    if (days == 0) return;
    final original = widget.task.endDate!;
    final updated = DateTime(original.year, original.month, original.day + days);
    widget.onDragEnd?.call(GanttDragResult(
      taskId: widget.task.id,
      newStartDate: widget.task.startDate,
      newEndDate: updated,
    ));
    _rightDelta = 0;
  }


}
