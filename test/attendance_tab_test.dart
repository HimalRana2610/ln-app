import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ln_app/features/attendance/application/attendance_controller.dart';
import 'package:ln_app/features/attendance/data/attendance_models.dart';
import 'package:ln_app/features/attendance/presentation/attendance_tab.dart';

const _classroomId = '82ad84fc-0f66-4357-a982-d46a23d592ee';

AttendanceSession _session({
  SessionStatus status = SessionStatus.active,
  RecordStatus? myStatus,
}) =>
    AttendanceSession(
      id: '11111111-2222-3333-4444-555555555555',
      classroomId: _classroomId,
      startedBy: 't',
      startedByName: 'Grace Hopper',
      date: '2026-09-14',
      status: status,
      startedAt: DateTime.utc(2026, 9, 14, 3, 15),
      verificationOpensAt: DateTime.utc(2026, 9, 14, 3, 20),
      radiusMeters: 15,
      thresholdMinutes: 5,
      rssiThreshold: -80,
      hopDepth: 2,
      sessionTag: '11111111',
      windowSeconds: 30,
      serverTime: DateTime.utc(2026, 9, 14, 3, 30),
      presentCount: 12,
      recordCount: 30,
      myStatus: myStatus,
    );

Future<void> _pump(
  WidgetTester tester,
  List<AttendanceSession> sessions, {
  required bool canManage,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        attendanceSessionsProvider.overrideWith((ref, id) async => sessions),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: AttendanceTab(classroomId: _classroomId, canManage: canManage),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a teacher sees the class count for each session',
      (tester) async {
    await _pump(tester, [_session()], canManage: true);
    await tester.pumpAndSettle();

    expect(find.text('12 of 30 present · Grace Hopper'), findsOneWidget);
    expect(find.text('Verification open'), findsOneWidget);
  });

  testWidgets('a student sees only their own status', (tester) async {
    await _pump(
      tester,
      [
        _session(status: SessionStatus.ended, myStatus: RecordStatus.present),
      ],
      canManage: false,
    );
    await tester.pumpAndSettle();

    expect(find.text('You: Present'), findsOneWidget);
    expect(find.textContaining('of 30 present'), findsNothing);
    expect(find.text('Ended'), findsOneWidget);
  });

  testWidgets('explains an empty list differently for each role',
      (tester) async {
    await _pump(tester, const [], canManage: false);
    await tester.pumpAndSettle();
    expect(find.textContaining('When your teacher starts a session'),
        findsOneWidget);
  });
}
