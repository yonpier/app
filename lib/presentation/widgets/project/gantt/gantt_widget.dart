import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:vikunja_app/domain/entities/project.dart';
import 'package:vikunja_app/domain/entities/task.dart';
import 'package:vikunja_app/l10n/gen/app_localizations.dart';
import 'package:vikunja_app/presentation/manager/project_controller.dart';
import 'package:vikunja_app/presentation/pages/error_widget.dart';
import 'package:vikunja_app/presentation/pages/loading_widget.dart';
import 'package:vikunja_app/presentation/pages/task/task_edit_page.dart';
import 'package:vikunja_app/presentation/widgets/project/gantt/_gantt_painter.dart';
import 'package:vikunja_app/presentation/widgets/project/gantt/_gantt_sort.dart';
import 'package:vikunja_app/presentation/widgets/project/gantt/_gantt_task_bar.dart';

/// Default number of months to show from the timeline start.
const int _kDefaultMonths = 12;

/// Number of months before the current month to start the timeline.
const int _kMonthOffset = 2;

// ---------------------------------------------------------------------------
// Auto-scroll constants (adapted from KanbanWidget)
// ---------------------------------------------------------------------------
const double _edgePx = 72;
const double _maxStep = 28;
const Duration _tick = Duration(milliseconds: 16);

// ---------------------------------------------------------------------------
// GanttWidget
// ---------------------------------------------------------------------------

/// Full Gantt-view widget for a [Project].
///
/// Displays a horizontal timeline with month headers, day grid lines, and
/// task bars that can be dragged to change dates or resized via handles.
/// Tapping a bar opens [TaskEditPage].
class GanttWidget extends ConsumerStatefulWidget {
  final Project project;

  const GanttWidget({super.key, required this.project});

  @override
  GanttWidgetState createState() => GanttWidgetState();
}

class GanttWidgetState extends ConsumerState<GanttWidget> {
  // -----------------------------------------------------------------------
  // Scroll controllers – linked so both header and task area scroll together
  // -----------------------------------------------------------------------
  late ScrollController _dateScrollController;
  late ScrollController _taskScrollController;

  // -----------------------------------------------------------------------
  // Timeline parameters
  // -----------------------------------------------------------------------
  late DateTime _timelineStart;
  int _totalDays = 0;
  double _dayWidth = 32;
  double _taskHeight = 44;
  bool _listenersAdded = false;

  // -----------------------------------------------------------------------
  // Drag state
  // -----------------------------------------------------------------------
  bool _dragActive = false;
  Offset? _lastGlobalDragPos;
  Timer? _autoScrollTimer;
  final GlobalKey _listKey = GlobalKey();

  /// State for bar drag (move) — null when not dragging a bar.
  ({int taskId, int touchDayOffset})? _dragState;
  /// Whether [_dragState.touchDayOffset] has been computed from the first update.
  bool _dragOffsetInitialized = false;
  /// Target day index (aligned to [_timelineStart]) during a bar drag.
  int? _dragTargetDay;

  // -----------------------------------------------------------------------
  // Task data – filtered + sorted from the controller
  // -----------------------------------------------------------------------
  List<Task> _ganttTasks = [];

  @override
  void initState() {
    super.initState();
    _dateScrollController = ScrollController();
    _taskScrollController = ScrollController();
  }

  @override
  void dispose() {
    _stopAutoScroll();
    if (_listenersAdded) {
      _dateScrollController.removeListener(_syncScrollToTask);
      _taskScrollController.removeListener(_syncScrollToDate);
    }
    _dateScrollController.dispose();
    _taskScrollController.dispose();
    super.dispose();
  }

  /// Recalculate timeline parameters from tasks and layout constraints.
  ///
  /// Layout-dependent sizing (`_dayWidth`, `_taskHeight`) and the timeline
  /// range (`_timelineStart`, `_totalDays`) are recomputed every time this
  /// is called. Only the scroll-controller listener wiring runs once.
  void _initTimeline(List<Task> tasks, BoxConstraints constraints) {
    _dayWidth = max(20, min(40, constraints.maxWidth / 15));
    _taskHeight = max(36, constraints.maxHeight / 18);

    // Determine timeline range from tasks or fallback to current month.
    DateTime? earliest;
    DateTime? latest;

    for (final t in tasks) {
      if (t.hasStartDate) {
        earliest = earliest == null || t.startDate!.isBefore(earliest)
            ? t.startDate
            : earliest;
        latest = latest == null || t.startDate!.isAfter(latest)
            ? t.startDate
            : latest;
      }
      if (t.hasEndDate) {
        latest = latest == null || t.endDate!.isAfter(latest)
            ? t.endDate
            : latest;
      }
    }

    final now = DateTime.now();
    if (earliest == null) {
      _timelineStart = DateTime(now.year, now.month - _kMonthOffset, 1);
    } else {
      _timelineStart = DateTime(
        earliest.year,
        earliest.month - 1,
        1,
      );
    }

    final endDate = latest ?? DateTime(now.year, now.month + _kDefaultMonths, 1);
    final endMonth = DateTime(endDate.year, endDate.month + 2, 1);
    _totalDays = endMonth.difference(_timelineStart).inDays;
    _totalDays = max(_totalDays, 60); // at least ~2 months

    // One-time wiring of scroll listeners and initial scroll-to-today.
    if (!_listenersAdded) {
      _dateScrollController.addListener(_syncScrollToTask);
      _taskScrollController.addListener(_syncScrollToDate);
      _listenersAdded = true;

      // Scroll to today (or earliest task) on first build.
      final scrollTarget = earliest ?? now;
      final offsetDays = scrollTarget.difference(_timelineStart).inDays;
      final initialOffset = offsetDays * _dayWidth - constraints.maxWidth / 3;
      if (initialOffset > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_dateScrollController.hasClients) {
            _dateScrollController.jumpTo(initialOffset.clamp(
              0,
              _dateScrollController.position.maxScrollExtent,
            ));
            _taskScrollController.jumpTo(initialOffset.clamp(
              0,
              _taskScrollController.position.maxScrollExtent,
            ));
          }
        });
      }
    }
  }

  void _syncScrollToTask() {
    if (_dateScrollController.hasClients &&
        _taskScrollController.hasClients &&
        _dateScrollController.offset != _taskScrollController.offset) {
      _taskScrollController.jumpTo(_dateScrollController.offset);
    }
  }

  void _syncScrollToDate() {
    if (_dateScrollController.hasClients &&
        _taskScrollController.hasClients &&
        _dateScrollController.offset != _taskScrollController.offset) {
      _dateScrollController.jumpTo(_taskScrollController.offset);
    }
  }

  // -----------------------------------------------------------------------
  // Build
  // -----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final controller =
        ref.watch(projectControllerProvider(widget.project));

    return controller.when(
      data: (data) {
        final allTasks = data.tasks;
        final dated = allTasks.where(hasGanttDates).toList();
        _ganttTasks = ganttSort(dated);

        if (_ganttTasks.isEmpty) {
          return Center(
            child: Text(
              AppLocalizations.of(context).ganttEmpty,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            _initTimeline(_ganttTasks, constraints);

            final totalWidth = _totalDays * _dayWidth;

            return Container(
              key: _listKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ---- Month header ----
                  _buildMonthHeader(totalWidth),
                  const Divider(height: 1),
                  // ---- Task rows ----
                  Expanded(child: _buildTaskArea(totalWidth)),
                ],
              ),
            );
          },
        );
      },
      error: (err, _) => VikunjaErrorWidget(error: err),
      loading: () => const LoadingWidget(),
    );
  }

  // -----------------------------------------------------------------------
  // Month header
  // -----------------------------------------------------------------------

  Widget _buildMonthHeader(double totalWidth) {
    final theme = Theme.of(context);

    // Walk through months between _timelineStart and _timelineStart + _totalDays.
    final months = <DateTime>[];
    final start = DateTime(_timelineStart.year, _timelineStart.month, 1);
    final end = DateTime(
      _timelineStart.year,
      _timelineStart.month,
      1,
    ).add(Duration(days: _totalDays));

    var cursor = start;
    while (cursor.isBefore(end)) {
      months.add(cursor);
      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }

    final monthHeaderHeight = _taskHeight * 1.6;

    return SizedBox(
      height: monthHeaderHeight,
      child: ListView.builder(
        controller: _dateScrollController,
        scrollDirection: Axis.horizontal,
        itemCount: months.length,
        itemBuilder: (context, index) {
          final month = months[index];
          final daysInMonth =
              DateTime(month.year, month.month + 1, 0).day;

          // Days from timelineStart to the start of this month.
          final monthStartOffset =
              month.difference(_timelineStart).inDays * _dayWidth;
          final monthWidth = daysInMonth * _dayWidth;

          return Container(
            width: monthWidth,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: theme.dividerColor,
                  width: 1,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Month name
                Container(
                  height: monthHeaderHeight * 0.4,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 4, top: 4),
                  child: Text(
                    DateFormat.yMMMM().format(month),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Day numbers
                Expanded(
                  child: ListView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    scrollDirection: Axis.horizontal,
                    itemCount: daysInMonth,
                    itemBuilder: (context, dayIndex) {
                      return Container(
                        width: _dayWidth,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border(
                            right: BorderSide(
                              color: theme.dividerColor.withValues(alpha: 0.3),
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: Text(
                          '${dayIndex + 1}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Task area
  // -----------------------------------------------------------------------

  Widget _buildTaskArea(double totalWidth) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SizedBox(
        height: _taskHeight * _ganttTasks.length,
        child: SingleChildScrollView(
          controller: _taskScrollController,
          scrollDirection: Axis.horizontal,
          child: CustomPaint(
            painter: ContainerPatternPainter(
              color: theme.dividerColor,
              dayWidth: _dayWidth,
              totalDays: _totalDays,
            ),
            child: SizedBox(
              width: totalWidth,
              height: _taskHeight * _ganttTasks.length,
              child: Stack(
                children: [
                  for (int i = 0; i < _ganttTasks.length; i++)
                    _buildTaskRow(_ganttTasks[i], i),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTaskRow(Task task, int index) {
    final hasStart = task.hasStartDate;
    final hasEnd = task.hasEndDate;
    final isBar = hasStart && hasEnd;

    int offsetDays;
    int durationDays;

    // ---- VISUAL FEEDBACK DURING DRAG ----
    // If this task is being dragged, use the drag target day for positioning
    // so the bar moves in real-time as the user drags.
    final bool isDragging =
        _dragState != null && _dragState!.taskId == task.id;
    if (isDragging && _dragTargetDay != null && isBar) {
      offsetDays = _dragTargetDay!;
      durationDays =
          max(1, task.endDate!.difference(task.startDate!).inDays);
    } else if (isBar) {
      offsetDays = task.startDate!.difference(_timelineStart).inDays;
      durationDays =
          max(1, task.endDate!.difference(task.startDate!).inDays);
    } else if (hasStart) {
      offsetDays = task.startDate!.difference(_timelineStart).inDays;
      durationDays = 1;
    } else {
      offsetDays = task.endDate!.difference(_timelineStart).inDays;
      durationDays = 1;
    }

    final left = offsetDays * _dayWidth;

    return Positioned(
      top: index * _taskHeight + _taskHeight * 0.15,
      left: left,
      child: GanttTaskBar(
        task: task,
        dayWidth: _dayWidth,
        taskHeight: _taskHeight,
        timelineStart: _timelineStart,
        offsetDays: offsetDays,
        durationDays: durationDays,
        isBar: isBar,
        onDragEnd: _onTaskDragEnd,
        onAnyDragStarted: _startAutoScroll,
        onAnyDragEnded: _stopAutoScroll,
        onAnyDragUpdate: _onDragUpdate,
        onTap: _openTaskEdit,
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Drag / resize → update dates
  // -----------------------------------------------------------------------

  Future<void> _onTaskDragEnd(GanttDragResult result) async {
    final taskId = result.taskId;
    final originalTask = _ganttTasks.cast<Task?>().firstWhere(
      (t) => t?.id == taskId,
      orElse: () => null as Task?,
    );
    if (originalTask == null) return;

    final updated = originalTask.copyWith(
      startDate: result.newStartDate,
      endDate: result.newEndDate,
    );

    if (!context.mounted) return;

    final ok = await ref
        .read(projectControllerProvider(widget.project).notifier)
        .updateTaskDates(updated);

    if (!context.mounted) return;

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).taskSaveError),
        ),
      );
    }
  }

  // -----------------------------------------------------------------------
  // Coordinate conversion
  // -----------------------------------------------------------------------

  /// Converts a global screen position to a timeline day index.
  /// Returns the day index (since [_timelineStart]) and the local X coordinate,
  /// or null when the position is outside the timeline.
  ({int dayIndex, double localX})? globalToTimelineDay(Offset globalPos) {
    final renderBox = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return null;

    final local = renderBox.globalToLocal(globalPos);
    final scrollOffset = _taskScrollController.hasClients
        ? _taskScrollController.position.pixels
        : 0.0;
    final timelineX = local.dx + scrollOffset;
    if (timelineX < 0) return null;

    final dayIndex = (timelineX / _dayWidth).floor();
    return (dayIndex: dayIndex, localX: local.dx);
  }

  // -----------------------------------------------------------------------
  // Tap → TaskEditPage
  // -----------------------------------------------------------------------

  void _openTaskEdit(Task task) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => TaskEditPage(task: task),
          ),
        )
        .then((_) {
          // Reload on return to pick up any changes.
          if (context.mounted) {
            ref
                .read(projectControllerProvider(widget.project).notifier)
                .reload();
          }
        });
  }

  // -----------------------------------------------------------------------
  // Drag auto-scroll + bar-drag date computation
  // -----------------------------------------------------------------------

  void _startAutoScroll([int? taskId]) {
    if (_dragActive) return;
    _dragActive = true;

    // Record drag state for bar drags (resize handles omit taskId).
    if (taskId != null) {
      _dragState = (taskId: taskId, touchDayOffset: 0);
      _dragOffsetInitialized = false;
      _dragTargetDay = null;
    }

    _autoScrollTimer ??= Timer.periodic(_tick, (_) => _autoScrollStep());
  }

  void _stopAutoScroll() {
    _dragActive = false;
    _lastGlobalDragPos = null;
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;

    // Finalize bar drag (resize handles are handled via onDragEnd).
    if (_dragState != null && _dragOffsetInitialized && _dragTargetDay != null) {
      _finalizeGanttDrag();
    }

    _dragState = null;
    _dragTargetDay = null;
    _dragOffsetInitialized = false;
  }

  void _onDragUpdate(Offset globalPos) {
    _lastGlobalDragPos = globalPos;

    // If a bar drag is active, compute the target day from absolute position.
    if (_dragState == null) return;

    final result = globalToTimelineDay(globalPos);
    if (result == null) return;

    if (!_dragOffsetInitialized) {
      // First update: compute the offset between touch point and task start.
      final task = _ganttTasks.cast<Task?>().firstWhere(
        (t) => t?.id == _dragState!.taskId,
        orElse: () => null as Task?,
      );
      if (task == null || !task.hasStartDate) {
        _dragState = null;
        return;
      }

      final taskStartDayIndex =
          task.startDate!.difference(_timelineStart).inDays;
      final touchDayIndex = result.dayIndex;
      final offset = touchDayIndex - taskStartDayIndex;

      _dragState = (taskId: _dragState!.taskId, touchDayOffset: offset);
      _dragOffsetInitialized = true;
      _dragTargetDay = taskStartDayIndex;
    } else {
      final targetDay = result.dayIndex - _dragState!.touchDayOffset;
      if (targetDay != _dragTargetDay) {
        _dragTargetDay = targetDay;
        setState(() {});
      }
    }
  }

  /// Called at the end of a bar drag to persist the new dates.
  Future<void> _finalizeGanttDrag() async {
    final state = _dragState;
    final targetDay = _dragTargetDay;
    if (state == null || targetDay == null || !mounted) return;

    final task = _ganttTasks.cast<Task?>().firstWhere(
      (t) => t?.id == state.taskId,
      orElse: () => null as Task?,
    );
    if (task == null || !task.hasStartDate || !task.hasEndDate) return;

    final newStart = DateTime(
      _timelineStart.year,
      _timelineStart.month,
      _timelineStart.day + targetDay,
    );

    final duration = task.endDate!.difference(task.startDate!).inDays;
    final newEnd = DateTime(
      newStart.year,
      newStart.month,
      newStart.day + duration,
    );

    final updated = task.copyWith(startDate: newStart, endDate: newEnd);

    if (!mounted) return;

    final ok = await ref
        .read(projectControllerProvider(widget.project).notifier)
        .updateTaskDates(updated);

    if (!mounted) return;

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).taskSaveError),
        ),
      );
    }
  }

  void _autoScrollStep() {
    if (!_dragActive ||
        _lastGlobalDragPos == null ||
        !_taskScrollController.hasClients) {
      return;
    }

    final box = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;

    final local = box.globalToLocal(_lastGlobalDragPos!);
    final size = box.size;

    // Pause if pointer is far outside the widget.
    if (local.dx < -50 ||
        local.dx > size.width + 50 ||
        local.dy < -50 ||
        local.dy > size.height + 50) {
      return;
    }

    double dx = 0;
    if (local.dx <= _edgePx) {
      final t = (1 - (local.dx / _edgePx)).clamp(0.0, 1.0);
      dx = -_maxStep * t;
    } else if (local.dx >= size.width - _edgePx) {
      final t =
          ((local.dx - (size.width - _edgePx)) / _edgePx).clamp(0.0, 1.0);
      dx = _maxStep * t;
    }

    if (dx.abs() > 0.1) {
      final next = (_taskScrollController.position.pixels + dx).clamp(
        _taskScrollController.position.minScrollExtent,
        _taskScrollController.position.maxScrollExtent,
      );
      if (next != _taskScrollController.position.pixels) {
        _taskScrollController.jumpTo(next);
        // The linked controller will follow via the listener.
      }
    }
  }
}
