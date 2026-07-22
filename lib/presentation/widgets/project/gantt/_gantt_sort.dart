import 'package:vikunja_app/domain/entities/task.dart';

/// Sorts tasks for the Gantt view according to algorithm A2:
///  1. Tasks with a non-null [startDate] come before tasks without.
///  2. Among tasks with [startDate]: ascending startDate, then descending id.
///  3. Among tasks without [startDate]: ascending endDate, then descending id.
///
/// Only call this on a list that has already been filtered to tasks that
/// have at least one of [startDate] / [endDate] (see [hasGanttDates]).
List<Task> ganttSort(List<Task> tasks) {
  int compare(Task a, Task b) {
    final sa = a.startDate;
    final sb = b.startDate;

    // Both have startDate → sort by startDate asc, then id desc.
    if (sa != null && sb != null) {
      final c = sa.compareTo(sb);
      return c != 0 ? c : b.id.compareTo(a.id);
    }

    // Neither has startDate → sort by endDate asc, then id desc.
    if (sa == null && sb == null) {
      final ea = a.endDate;
      final eb = b.endDate;
      if (ea != null && eb != null) {
        final c = ea.compareTo(eb);
        return c != 0 ? c : b.id.compareTo(a.id);
      }
      // One (or both) have no endDate either (shouldn't happen after
      // filtering, but handle it defensively).
      if (ea == null && eb == null) return b.id.compareTo(a.id);
      return ea == null ? 1 : -1;
    }

    // A2: tasks with startDate go before those without.
    return sa == null ? 1 : -1;
  }

  final sorted = [...tasks];
  sorted.sort(compare);
  return sorted;
}

/// Returns `true` when at least one of [startDate] / [endDate] is set and
/// not on year 1 (the "null" sentinel used by the API).
bool hasGanttDates(Task task) {
  return task.hasStartDate || task.hasEndDate;
}
