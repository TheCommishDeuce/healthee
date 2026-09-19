/// The SSE framing itself — no HTTP, no JSON, no Dio.
///
/// `coach_client_stream_test.dart` is the layer above this: it drives
/// [parseSseStream] through a fake Dio adapter and asserts this app's own
/// exceptions come out the other end. This suite is about the framing alone,
/// including the failure modes a live TCP stream actually has: a chunk
/// splitting a line, or a block, mid-way; `\r\n` beside `\n`; a trailing block
/// with no final blank line.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/coach/sse_parser.dart';

/// One chunk per call — the common case, a whole block in one read.
Stream<List<int>> _wholeChunk(String text) => Stream.value(utf8.encode(text));

/// [text] split into two chunks at byte offset [at] — the uncommon case a
/// live socket actually produces, and the one worth pinning: nothing here may
/// assume a chunk boundary lines up with a line or a block boundary.
Stream<List<int>> _splitAt(String text, int at) {
  final bytes = utf8.encode(text);
  return Stream.fromIterable(<List<int>>[
    bytes.sublist(0, at),
    bytes.sublist(at),
  ]);
}

Future<List<SseEvent>> _collect(Stream<List<int>> bytes) =>
    parseSseStream(bytes).toList();

void main() {
  test('a plain data-only block names its event "message"', () async {
    final events = await _collect(_wholeChunk('data: hello\n\n'));

    expect(events, hasLength(1));
    expect(events.single.event, 'message');
    expect(events.single.data, 'hello');
  });

  test('an `event:` field names the block', () async {
    final events = await _collect(
      _wholeChunk('event: stage\ndata: {"stage":"context"}\n\n'),
    );

    expect(events.single.event, 'stage');
    expect(events.single.data, '{"stage":"context"}');
  });

  test('several `data:` lines in one block join with a newline', () async {
    // The SSE spec's own rule — a multi-line JSON body, say, arrives as
    // several `data:` lines and must be reassembled before it is decoded.
    final events = await _collect(
      _wholeChunk('event: answer\ndata: {"reply":\ndata: "two lines"}\n\n'),
    );

    expect(events.single.data, '{"reply":\n"two lines"}');
  });

  test('a comment line carries nothing and starts nothing', () async {
    final events = await _collect(_wholeChunk(': keepalive\ndata: real\n\n'));

    expect(events, hasLength(1));
    expect(events.single.data, 'real');
  });

  test('a comment-only block dispatches no event at all', () async {
    final events = await _collect(_wholeChunk(': just a comment\n\n'));

    expect(events, isEmpty);
  });

  test('CRLF line endings parse exactly like LF', () async {
    final events = await _collect(
      _wholeChunk('event: stage\r\ndata: {"stage":"thinking"}\r\n\r\n'),
    );

    expect(events.single.event, 'stage');
    expect(events.single.data, '{"stage":"thinking"}');
  });

  test('only ONE leading space after the colon is dropped', () async {
    // The spec drops at most one; a second one is part of the value.
    final events = await _collect(_wholeChunk('data:  two spaces\n\n'));

    expect(events.single.data, ' two spaces');
  });

  test('an unknown event name still parses — never crashes', () async {
    // Ignoring a name this app does not know is `CoachClient`'s job, not the
    // framing's: the parser must hand every block up rather than deciding
    // which ones matter.
    final events = await _collect(
      _wholeChunk('event: a_future_event\ndata: {}\n\n'),
    );

    expect(events.single.event, 'a_future_event');
  });

  group('a chunk boundary lands mid-way', () {
    const String twoBlocks =
        'event: stage\ndata: {"stage":"context"}\n\n'
        'event: answer\ndata: {"reply":"done"}\n\n';

    test('splitting a LINE does not lose or duplicate it', () async {
      // Cuts inside "event: stage" — a boundary a UTF-8-safe reader must
      // buffer across, not one this parser gets to assume never happens.
      final events = await _collect(_splitAt(twoBlocks, 8));

      expect(events, hasLength(2));
      expect(events[0].event, 'stage');
      expect(events[1].event, 'answer');
    });

    test(
      'splitting the BLANK LINE between two blocks keeps them separate',
      () async {
        final int blankLineAt = twoBlocks.indexOf('\n\n') + 1;
        final events = await _collect(_splitAt(twoBlocks, blankLineAt));

        expect(events, hasLength(2));
        expect(events[0].data, '{"stage":"context"}');
        expect(events[1].data, '{"reply":"done"}');
      },
    );
  });

  test(
    'a trailing block with no final blank line is still dispatched',
    () async {
      // A server that closes the connection right after its last `data:` line,
      // with no terminating blank line — the stream's own `done` must still
      // flush whatever was buffered.
      final events = await _collect(
        _wholeChunk('event: answer\ndata: {"ok":true}'),
      );

      expect(events, hasLength(1));
      expect(events.single.event, 'answer');
      expect(events.single.data, '{"ok":true}');
    },
  );

  test('an empty stream yields no events', () async {
    final events = await _collect(const Stream.empty());

    expect(events, isEmpty);
  });
}
