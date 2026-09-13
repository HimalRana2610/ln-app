import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../application/quiz_controller.dart';
import '../application/quiz_poller.dart';
import '../data/quiz_models.dart';

/// A classroom's live quiz: polls while on screen, and renders [QuizView].
class QuizTab extends ConsumerStatefulWidget {
  const QuizTab({
    required this.classroomId,
    required this.canManage,
    required this.visible,
    super.key,
  });

  final String classroomId;
  final bool canManage;

  /// Whether this tab is the selected one. `TabBarView` keeps neighbouring
  /// tabs built, so being built is not the same as being seen.
  final bool visible;

  @override
  ConsumerState<QuizTab> createState() => _QuizTabState();
}

class _QuizTabState extends ConsumerState<QuizTab> with WidgetsBindingObserver {
  late final QuizPoller _poller = QuizPoller(
    fetch: () => ref.read(quizRepositoryProvider).state(widget.classroomId),
  );

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _poller
      ..setResumed(lifecycle == null || lifecycle == AppLifecycleState.resumed)
      ..setVisible(widget.visible);
  }

  @override
  void didUpdateWidget(QuizTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) {
      _poller.setVisible(widget.visible);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _poller.setResumed(true);
      case AppLifecycleState.paused ||
            AppLifecycleState.hidden ||
            AppLifecycleState.detached:
        _poller.setResumed(false);
      case AppLifecycleState.inactive:
        // A notification shade or a permission dialog; the quiz is still
        // visible behind it, so keep polling.
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poller.dispose();
    super.dispose();
  }

  /// Runs an action, shows its error, and re-polls so the result appears now
  /// rather than at the next tick.
  Future<bool> _run(Future<void> Function() action) async {
    if (_busy) return false;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await action();
      await _poller.refresh();
      return true;
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
      // A 409 usually means the screen was behind; catch up.
      await _poller.refresh();
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.read(quizRepositoryProvider);

    return ListenableBuilder(
      listenable: Listenable.merge([_poller.state, _poller.error]),
      builder: (context, _) {
        final state = _poller.state.value;
        final error = _poller.error.value;

        if (state == null) {
          return Center(
            child: error == null
                ? const CircularProgressIndicator()
                : Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      error is ApiException ? error.message : '$error',
                      textAlign: TextAlign.center,
                    ),
                  ),
          );
        }

        return RefreshIndicator(
          onRefresh: _poller.refresh,
          child: QuizView(
            state: state,
            canManage: widget.canManage,
            busy: _busy,
            onAnswer: (question, option) =>
                _run(() => repository.answer(question.id, option)),
            onEnd: (question) => _run(() => repository.end(question.id)),
            onAsk: (prompt, options, correct) => _run(
              () => repository.ask(
                widget.classroomId,
                prompt: prompt,
                options: options,
                correctOption: correct,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The quiz for one state snapshot. Stateless apart from the composer's form,
/// so it can be tested without a network or a poller.
class QuizView extends StatelessWidget {
  const QuizView({
    required this.state,
    required this.canManage,
    required this.onAnswer,
    required this.onEnd,
    required this.onAsk,
    this.busy = false,
    super.key,
  });

  final QuizState state;
  final bool canManage;
  final bool busy;
  final Future<bool> Function(QuizQuestion question, String option) onAnswer;
  final Future<bool> Function(QuizQuestion question) onEnd;
  final Future<bool> Function(
      String prompt, List<String> options, String correctOption) onAsk;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = state.active;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      children: [
        if (active != null)
          _ActiveQuestion(
            question: active,
            canManage: canManage,
            busy: busy,
            onAnswer: onAnswer,
            onEnd: onEnd,
          )
        else if (canManage)
          _Composer(busy: busy, onAsk: onAsk)
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No question right now. When your teacher asks one, it '
                'appears here.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
        const SizedBox(height: 16),
        Text('Leaderboard', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (state.leaderboard.isEmpty)
          Text('No answers yet.', style: theme.textTheme.bodySmall)
        else
          Card(
            child: Column(
              children: [
                // Server order, verbatim: it already breaks ties on penalty.
                for (final entry in state.leaderboard)
                  ListTile(
                    key: ValueKey('leader-${entry.studentId}'),
                    dense: true,
                    leading: CircleAvatar(
                      radius: 14,
                      child: Text('${entry.rank}',
                          style: const TextStyle(fontSize: 12)),
                    ),
                    title: Text(entry.studentName),
                    subtitle: Text(
                      '${entry.penaltySeconds.toStringAsFixed(1)}s penalty',
                    ),
                    trailing: Text('${entry.correct}/${entry.answered}'),
                  ),
              ],
            ),
          ),
        if (state.recent.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Recent questions', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final question in state.recent)
            Card(
              child: ListTile(
                title: Text(question.prompt),
                subtitle: Text([
                  if (question.correctOption != null)
                    'Answer ${question.correctOption}',
                  '${question.answerCount} answered',
                  if (question.myOption != null)
                    'You: ${question.myOption}'
                        '${question.myIsCorrect == true ? ' ✓' : question.myIsCorrect == false ? ' ✗' : ''}',
                ].join(' · ')),
              ),
            ),
        ],
      ],
    );
  }
}

class _ActiveQuestion extends StatelessWidget {
  const _ActiveQuestion({
    required this.question,
    required this.canManage,
    required this.busy,
    required this.onAnswer,
    required this.onEnd,
  });

  final QuizQuestion question;
  final bool canManage;
  final bool busy;
  final Future<bool> Function(QuizQuestion question, String option) onAnswer;
  final Future<bool> Function(QuizQuestion question) onEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Students never pick again: the server stores one answer each.
    final canAnswer = !canManage && !question.hasAnswered && !busy;

    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('LIVE · ${question.answerCount} answered',
                style: theme.textTheme.labelSmall),
            const SizedBox(height: 8),
            Text(question.prompt, style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            for (var i = 0; i < question.options.length && i < 4; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _OptionButton(
                  letter: quizOptionLetters[i],
                  text: question.options[i],
                  // Present only when the server chose to reveal it: always
                  // for teachers, never for students while the question is live.
                  isCorrect: question.correctOption == quizOptionLetters[i],
                  isMine: question.myOption == quizOptionLetters[i],
                  onPressed: canAnswer
                      ? () => onAnswer(question, quizOptionLetters[i])
                      : null,
                ),
              ),
            if (!canManage && question.hasAnswered)
              Text(
                'You answered ${question.myOption}. The answer is revealed '
                'when the question ends.',
                style: theme.textTheme.bodySmall,
              ),
            if (canManage)
              FilledButton.icon(
                onPressed: busy ? null : () => onEnd(question),
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('End question'),
              ),
          ],
        ),
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  const _OptionButton({
    required this.letter,
    required this.text,
    required this.isCorrect,
    required this.isMine,
    required this.onPressed,
  });

  final String letter;
  final String text;
  final bool isCorrect;
  final bool isMine;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return OutlinedButton(
      key: ValueKey('option-$letter'),
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        backgroundColor: isMine ? scheme.secondaryContainer : scheme.surface,
        side: BorderSide(
          color: isCorrect ? Colors.green : scheme.outlineVariant,
          width: isCorrect ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Text('$letter.', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
          if (isCorrect)
            const Icon(Icons.check_circle,
                color: Colors.green, size: 18, semanticLabel: 'Correct'),
        ],
      ),
    );
  }
}

class _Composer extends StatefulWidget {
  const _Composer({required this.busy, required this.onAsk});

  final bool busy;
  final Future<bool> Function(
      String prompt, List<String> options, String correctOption) onAsk;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _formKey = GlobalKey<FormState>();
  final _prompt = TextEditingController();
  final _options = List.generate(4, (_) => TextEditingController());
  String _correct = 'A';

  @override
  void dispose() {
    _prompt.dispose();
    for (final controller in _options) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await widget.onAsk(
      _prompt.text.trim(),
      [for (final controller in _options) controller.text.trim()],
      _correct,
    );
    if (!ok || !mounted) return;
    _prompt.clear();
    for (final controller in _options) {
      controller.clear();
    }
    setState(() => _correct = 'A');
  }

  static String? _required(String? value) =>
      (value == null || value.trim().isEmpty) ? 'Required' : null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Ask a question', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              TextFormField(
                controller: _prompt,
                decoration: const InputDecoration(labelText: 'Question'),
                validator: _required,
                maxLines: null,
              ),
              for (var i = 0; i < 4; i++) ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _options[i],
                  decoration: InputDecoration(
                      labelText: 'Option ${quizOptionLetters[i]}'),
                  validator: _required,
                ),
              ],
              const SizedBox(height: 12),
              Text('Correct answer', style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              SegmentedButton<String>(
                segments: [
                  for (final letter in quizOptionLetters)
                    ButtonSegment(value: letter, label: Text(letter)),
                ],
                selected: {_correct},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    setState(() => _correct = selection.first),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: widget.busy ? null : _submit,
                icon: const Icon(Icons.send),
                label: const Text('Ask'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
