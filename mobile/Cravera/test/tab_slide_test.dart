// Tab page slide (TASK-UI-3, deferred P2 from PR #22).
import 'package:cravera/core/routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a page sent away while still sliding in leaves from where it is, without a jump', () {
    // Arrives from the right (+1); at 40% in, the next tab (further right)
    // sends it out to the left (-1).
    final slide = TabSlide(enterFrom: 1);
    double? last;
    for (final t in [0.0, 0.2, 0.4]) {
      last = slide.offset(t, leaving: false, exitTo: -1);
    }
    expect(last, closeTo(0.15, 1e-9), reason: 'still on the right');

    final out = [for (final t in [0.4, 0.3, 0.2, 0.1, 0.0]) slide.offset(t, leaving: true, exitTo: -1)];
    expect(out.first, closeTo(last!, 1e-9), reason: 'the first leaving frame starts where it was');
    for (var i = 1; i < out.length; i++) {
      expect(out[i], lessThan(out[i - 1]), reason: 'moves left every frame');
      expect(out[i - 1] - out[i], lessThan(0.11), reason: 'in even steps, no jump');
    }
    expect(out.last, closeTo(-TabSlide.distance, 1e-9), reason: 'ends fully out on the left');
  });

  test('a settled page leaves the usual way, and the exit side is picked once', () {
    final slide = TabSlide(enterFrom: -1);
    expect(slide.offset(1, leaving: false, exitTo: 1), 0);
    expect(slide.offset(1, leaving: true, exitTo: 1), 0);
    expect(slide.offset(0.5, leaving: true, exitTo: 1), closeTo(0.125, 1e-9));
    // A later tap in the other direction doesn't flip a page already leaving.
    expect(slide.offset(0, leaving: true, exitTo: -1), closeTo(0.25, 1e-9));
  });

  test('entering from either side starts a quarter width away', () {
    expect(TabSlide(enterFrom: 1).offset(0, leaving: false, exitTo: -1), closeTo(0.25, 1e-9));
    expect(TabSlide(enterFrom: -1).offset(0, leaving: false, exitTo: 1), closeTo(-0.25, 1e-9));
  });
}
