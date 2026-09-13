import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../application/security_controller.dart';
import '../data/security_models.dart';

/// Teacher tools for one class: alerts, then each student's status with block,
/// unblock and reset. Ported from `TeacherDeviceManagement` and
/// `TeacherNotifications`.
class StudentSecurityScreen extends ConsumerWidget {
  const StudentSecurityScreen({
    required this.classroomId,
    required this.classroomName,
    super.key,
  });

  final String classroomId;
  final String classroomName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final students = ref.watch(studentSecurityProvider(classroomId));
    final alerts = ref.watch(securityAlertsProvider(classroomId));

    Future<void> refresh() async {
      ref
        ..invalidate(studentSecurityProvider(classroomId))
        ..invalidate(securityAlertsProvider(classroomId));
    }

    Future<void> run(Future<void> Function() action) async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await action();
        await refresh();
      } on ApiException catch (error) {
        messenger.showSnackBar(SnackBar(content: Text(error.message)));
      }
    }

    final repository = ref.read(securityRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: Text('Security · $classroomName')),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
          children: [
            const _Heading('Alerts'),
            alerts.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('$e'),
              data: (list) => list.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Nothing suspicious so far.'),
                    )
                  : Column(
                      children: [
                        for (final alert in list)
                          AlertTile(
                            alert: alert,
                            onDismiss: () =>
                                run(() => repository.markAlertRead(alert.id)),
                          ),
                      ],
                    ),
            ),
            const _Heading('Students'),
            students.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('$e'),
              data: (list) => Column(
                children: [
                  for (final student in list)
                    StudentSecurityTile(
                      student: student,
                      onBlock: (reason) => run(() => repository.setBlock(
                            classroomId,
                            student.studentId,
                            blocked: true,
                            reason: reason,
                          )),
                      onUnblock: () => run(() => repository.setBlock(
                            classroomId,
                            student.studentId,
                            blocked: false,
                          )),
                      onReset: () => run(() => repository.resetEnrollment(
                          classroomId, student.studentId)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}

class AlertTile extends StatelessWidget {
  const AlertTile({required this.alert, required this.onDismiss, super.key});

  final SecurityAlert alert;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unread = alert.readAt == null;
    return Card(
      color: unread && alert.critical ? scheme.errorContainer : null,
      child: ListTile(
        leading: Icon(
          alert.critical ? Icons.gpp_bad : Icons.gpp_maybe,
          color: alert.critical ? scheme.error : Colors.amber.shade800,
        ),
        title: Text('${alert.studentName} · ${alert.label}'),
        subtitle: Text(alert.message),
        trailing: unread
            ? TextButton(onPressed: onDismiss, child: const Text('Dismiss'))
            : null,
      ),
    );
  }
}

class StudentSecurityTile extends StatelessWidget {
  const StudentSecurityTile({
    required this.student,
    required this.onBlock,
    required this.onUnblock,
    required this.onReset,
    super.key,
  });

  final StudentSecurity student;
  final void Function(String? reason) onBlock;
  final VoidCallback onUnblock;
  final VoidCallback onReset;

  Future<void> _confirmBlock(BuildContext context) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Block ${student.fullName}?'),
        content: TextField(
          controller: reason,
          decoration: const InputDecoration(
            labelText: 'Reason they will see (optional)',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Block')),
        ],
      ),
    );
    if (ok == true) {
      onBlock(reason.text.trim().isEmpty ? null : reason.text.trim());
    }
  }

  Future<void> _confirmReset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Reset ${student.fullName}?'),
        content: const Text(
            'Their phone is unbound and face data deleted in every class, so they can set up a new phone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Reset')),
        ],
      ),
    );
    if (ok == true) onReset();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final facts = [
      student.emailVerified ? 'Email verified' : 'Email unverified',
      student.device == null ? 'No phone' : 'Phone: ${student.device!.label}',
      if (student.faceEnrolled) 'Face enrolled',
      if (student.blocked)
        'BLOCKED${student.blockReason == null ? '' : ': ${student.blockReason}'}',
    ];

    return Card(
      child: ListTile(
        leading: Badge(
          isLabelVisible: student.unreadAlerts > 0,
          label: Text('${student.unreadAlerts}'),
          child: Icon(
            student.blocked ? Icons.block : Icons.person_outline,
            color: student.blocked ? scheme.error : null,
          ),
        ),
        title: Text(student.fullName),
        subtitle: Text(facts.join(' · ')),
        trailing: PopupMenuButton<String>(
          tooltip: 'Actions',
          onSelected: (value) => switch (value) {
            'block' => _confirmBlock(context),
            'unblock' => onUnblock(),
            'reset' => _confirmReset(context),
            _ => null,
          },
          itemBuilder: (_) => [
            if (student.blocked)
              const PopupMenuItem(value: 'unblock', child: Text('Unblock'))
            else
              const PopupMenuItem(value: 'block', child: Text('Block')),
            if (student.device != null || student.faceEnrolled)
              const PopupMenuItem(
                  value: 'reset', child: Text('Reset enrolment')),
          ],
        ),
      ),
    );
  }
}
