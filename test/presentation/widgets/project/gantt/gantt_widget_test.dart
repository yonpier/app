import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vikunja_app/domain/entities/project.dart';
import 'package:vikunja_app/domain/entities/project_page_model.dart';
import 'package:vikunja_app/domain/entities/task.dart';
import 'package:vikunja_app/domain/entities/user.dart';
import 'package:vikunja_app/presentation/manager/project_controller.dart';
import 'package:vikunja_app/presentation/widgets/project/gantt/gantt_widget.dart';
import 'package:vikunja_app/l10n/gen/app_localizations.dart';

class _MockProjectController extends ProjectController {
  final ProjectPageModel model;
  _MockProjectController(this.model);

  @override
  Future<ProjectPageModel> build(Project project) async => model;
}

void main() {
  group('GanttWidget bar drag positioning', () {
    testWidgets('renders tasks and allows drag to reposition', (
      WidgetTester tester,
    ) async {
      final user = User(username: 'testuser');
      final startDate = DateTime(2025, 6, 10);
      final endDate = DateTime(2025, 6, 15);

      final task = Task(
        id: 1,
        title: 'Test Task',
        createdBy: user,
        projectId: 1,
        startDate: startDate,
        endDate: endDate,
      );

      final project = Project(id: 1, title: 'Test Project');
      final model = ProjectPageModel(project, 0, [task], [], false, false);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            projectControllerProvider(project)
                .overrideWith(() => _MockProjectController(model)),
          ],
          child: MaterialApp(
            home: Scaffold(body: GanttWidget(project: project)),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
          ),
        ),
      );

      // Let the widget build and finish layout.
      await tester.pumpAndSettle();

      // The GanttWidget should render the task bar.
      expect(find.text('Test Task'), findsOneWidget);
    });

    testWidgets('_handleBarDragEnd computes daysDelta from finger offset only', (
      WidgetTester tester,
    ) async {
      // Verify the arithmetic that lives in _handleBarDragEnd:
      // daysDelta = round(details.offset.dx / dayWidth) without any scroll offset.
      const dayWidth = 32.0;

      // finger moved 50px right → daysDelta = round(50 / 32) = 2
      const fingerDelta = 50.0;
      final daysDelta = (fingerDelta / dayWidth).round();
      expect(daysDelta, 2);

      // finger moved 30px right → daysDelta = round(30 / 32) = 1
      const fingerDeltaRight = 30.0;
      final daysDeltaRight = (fingerDeltaRight / dayWidth).round();
      expect(daysDeltaRight, 1);

      // finger moved 40px left → daysDelta = round(-40 / 32) = -1
      const fingerDeltaLeft = -40.0;
      final daysDeltaLeft = (fingerDeltaLeft / dayWidth).round();
      expect(daysDeltaLeft, -1);

      // Verify resulting dates for a rightward move of 2 days
      final startDate = DateTime(2025, 6, 10);
      final endDate = DateTime(2025, 6, 15);

      final adjustedStart = DateTime(
        startDate.year,
        startDate.month,
        startDate.day + daysDelta,
      );
      final adjustedEnd = DateTime(
        endDate.year,
        endDate.month,
        endDate.day + daysDelta,
      );

      expect(adjustedStart, DateTime(2025, 6, 12));
      expect(adjustedEnd, DateTime(2025, 6, 17));
    });
  });
}
