import 'package:cucumber_core/engine.dart';
import 'package:cucumber_core/src/runtime/ids.dart' show fnv64;
import 'package:cucumber_messages/cucumber_messages.dart' as messages;
import 'package:stack_trace/stack_trace.dart';
import 'package:test/test.dart';

void main() {
  group('ids', () {
    test('fnv64 matches the FNV-1a 64-bit reference vectors', () {
      expect(fnv64(''), 'cbf29ce484222325');
      expect(fnv64('a'), 'af63dc4c8601ec8c');
      expect(fnv64('foobar'), '85944171f73967e8');
    });

    test('incrementing scheme shares one counter', () {
      final ids = IdScheme.incrementing();
      expect(ids.forSource('a.feature').newId(), '0');
      expect(ids.forGlue(0, 'x'), '1');
      expect(ids.newId(), '2');
    });

    test('deterministic scheme gives stable static IDs', () {
      final a = IdScheme.deterministic();
      final b = IdScheme.deterministic();
      final ga = a.forSource('features/x.feature');
      final gb = b.forSource('features/x.feature');
      expect([ga.newId(), ga.newId()], [gb.newId(), gb.newId()]);
      expect(ga.newId(), startsWith('${fnv64('features/x.feature')}-'));
      expect(a.forGlue(3, 'k'), b.forGlue(3, 'k'));
      expect(a.forGlue(3, 'k'), isNot(a.forGlue(4, 'k')));
      expect(a.newId(), isNot(b.newId()));
    });

    test('UUIDs are version 4', () {
      final id = UuidIdGenerator().newId();
      expect(
        id,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
            r'[0-9a-f]{12}$',
          ),
        ),
      );
    });
  });

  group('MessageBus', () {
    messages.Envelope source(String uri) => messages.Envelope(
      source: messages.Source(
        uri: uri,
        data: '',
        mediaType: messages.SourceMediaType.textXCucumberGherkinPlain,
      ),
    );

    test('buffers until started', () {
      final plugin = CollectingPlugin();
      final bus = MessageBus([plugin])..emit(source('a'));
      expect(plugin.envelopes, isEmpty);
      bus
        ..start()
        ..emit(source('b'));
      expect(plugin.envelopes.map((e) => e.source!.uri), ['a', 'b']);
    });

    test('discards the buffer when closed without starting', () async {
      final plugin = CollectingPlugin();
      final bus = MessageBus([plugin])..emit(source('a'));
      await bus.close();
      expect(plugin.envelopes, isEmpty);
      expect(plugin.isClosed, isTrue);
      expect(() => bus.emit(source('b')), throwsStateError);
    });
  });

  group('Status', () {
    test('is ordered by severity', () {
      expect(Status.failed.isWorseThan(Status.ambiguous), isTrue);
      expect(Status.skipped.worst(Status.pending), Status.pending);
      expect(Status.skipped.isFailedish, isFalse);
      expect(Status.undefined.isFailedish, isTrue);
      for (final status in Status.values) {
        expect(Status.fromMessage(status.toMessage()), status);
      }
    });
  });

  group('PickleOrder', () {
    test('parses specifications', () {
      expect(PickleOrder.parse('defined'), PickleOrder.defined);
      expect(PickleOrder.parse('reverse'), PickleOrder.reverse);
      expect((PickleOrder.parse('random:42') as RandomOrder).seed, 42);
      expect(PickleOrder.parse('random'), isA<RandomOrder>());
      expect(() => PickleOrder.parse('sideways'), throwsArgumentError);
    });

    test('random order is reproducible with its seed', () {
      final items = List.generate(20, (i) => i);
      final order = RandomOrder();
      expect(order.apply(items), RandomOrder(order.seed).apply(items));
      expect(order.apply(items), unorderedEquals(items));
    });
  });

  group('SourceReference', () {
    test('glue records where it was constructed', () {
      final glue = Given('x', () {});
      expect(glue.source, isNotNull);
      expect(glue.source!.uri, endsWith('foundations_test.dart'));
      expect(glue.source!.line, greaterThan(0));
    });

    test('records the line of the closest user frame', () {
      final line = Trace.current().frames.first.line!;
      final direct = Given('x', () {});
      Glue helper() => When('y', () {});
      final viaHelper = helper();
      expect(direct.source!.uri, 'test/runtime/foundations_test.dart');
      expect(direct.source!.line, line + 1);
      expect(direct.source!.column, isNotNull);
      expect(viaHelper.source!.line, line + 2);
    });
  });
}
