import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ln_app/features/quiz/application/quiz_poller.dart';
import 'package:ln_app/features/quiz/data/quiz_models.dart';

void main() {
  group('QuizPoller', () {
    test('polls only while visible, at the interval the server sends', () {
      fakeAsync((async) {
        var calls = 0;
        final poller = QuizPoller(fetch: () async {
          calls++;
          return const QuizState(pollIntervalSeconds: 5);
        });

        // Built but not on screen: nothing.
        async.elapse(const Duration(seconds: 30));
        expect(calls, 0);

        poller.setVisible(true);
        async.flushMicrotasks();
        expect(calls, 1, reason: 'fetches at once when shown');
        expect(poller.interval, const Duration(seconds: 5));

        async.elapse(const Duration(seconds: 4));
        expect(calls, 1);
        async.elapse(const Duration(seconds: 1));
        expect(calls, 2);
        async.elapse(const Duration(seconds: 10));
        expect(calls, 4);

        poller.setVisible(false);
        async.elapse(const Duration(minutes: 1));
        expect(calls, 4, reason: 'hidden tab makes no requests');

        poller.dispose();
      });
    });

    test('follows a changed interval from the server', () {
      fakeAsync((async) {
        var calls = 0;
        final poller = QuizPoller(fetch: () async {
          calls++;
          return QuizState(pollIntervalSeconds: calls == 1 ? 2 : 10);
        });

        poller.setVisible(true);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));
        expect(calls, 2);
        async.elapse(const Duration(seconds: 9));
        expect(calls, 2);
        async.elapse(const Duration(seconds: 1));
        expect(calls, 3);

        poller.dispose();
      });
    });

    test('stops when the app is paused and resumes with a fresh fetch', () {
      fakeAsync((async) {
        var calls = 0;
        final poller = QuizPoller(fetch: () async {
          calls++;
          return const QuizState(pollIntervalSeconds: 3);
        });

        poller.setVisible(true);
        async.flushMicrotasks();
        expect(calls, 1);

        poller.setResumed(false);
        async.elapse(const Duration(minutes: 5));
        expect(calls, 1);

        poller.setResumed(true);
        async.flushMicrotasks();
        expect(calls, 2);
        async.elapse(const Duration(seconds: 3));
        expect(calls, 3);

        poller.dispose();
        async.elapse(const Duration(minutes: 1));
        expect(calls, 3, reason: 'dispose cancels the timer');
      });
    });

    test('a request in flight when hidden does not re-arm the timer', () {
      fakeAsync((async) {
        var calls = 0;
        final poller = QuizPoller(fetch: () async {
          calls++;
          await Future<void>.delayed(const Duration(seconds: 1));
          return const QuizState(pollIntervalSeconds: 3);
        });

        poller.setVisible(true);
        poller.setVisible(false);
        async.elapse(const Duration(minutes: 1));
        expect(calls, 1);
        expect(poller.state.value, isNotNull);

        poller.dispose();
      });
    });

    test('keeps the last state when a poll fails', () {
      fakeAsync((async) {
        var calls = 0;
        final poller = QuizPoller(fetch: () async {
          calls++;
          if (calls == 2) throw Exception('offline');
          return const QuizState(pollIntervalSeconds: 3);
        });

        poller.setVisible(true);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 3));
        expect(poller.state.value, isNotNull);
        expect(poller.error.value, isNotNull);

        async.elapse(const Duration(seconds: 3));
        expect(calls, 3, reason: 'keeps polling after a failure');
        expect(poller.error.value, isNull);

        poller.dispose();
      });
    });
  });
}
