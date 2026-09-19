/// Server-Sent Events framing, and nothing else — no HTTP, no JSON, no Dio.
///
/// Kept pure Dart so its tests exercise the actual failure modes of a live TCP
/// stream (a chunk splitting a line, or a block, mid-way; `\r\n` beside `\n`; a
/// trailing block with no final blank line) without a fake HTTP client
/// standing in for any of them. [CoachClient.askStream] is the one caller.
///
/// The framing, per the SSE spec: blocks are separated by a blank line; a line
/// starting with `:` is a comment and carries nothing; a `field:value` line's
/// value drops at most one leading space; several `data:` lines in one block
/// join with `\n`; any field this app does not use (`id`, `retry`) is valid
/// SSE and is simply not surfaced.
library;

import 'dart:convert';

/// One parsed event — a name (`message` when the block named none, the spec's
/// own default) and its `data:` lines joined with `\n`.
class SseEvent {
  /// Built by [parseSseStream].
  const SseEvent({required this.event, required this.data});

  /// The block's `event:` field, or `message` when it had none.
  final String event;

  /// Every `data:` line in the block, joined with `\n`.
  final String data;
}

/// Turns a raw byte stream into the SSE events it frames.
///
/// Chunk boundaries are the transport's problem, not this function's: bytes
/// may split a UTF-8 sequence, a line or a block anywhere, and [utf8.decoder]
/// composed with [LineSplitter] already buffer exactly that correctly — this
/// function only ever sees whole decoded lines.
Stream<SseEvent> parseSseStream(Stream<List<int>> bytes) async* {
  String? eventName;
  final List<String> dataLines = <String>[];

  final Stream<String> lines = utf8.decoder
      .bind(bytes)
      .transform(const LineSplitter());
  await for (final String line in lines) {
    if (line.isEmpty) {
      final SseEvent? event = _dispatch(eventName, dataLines);
      if (event != null) {
        yield event;
      }
      eventName = null;
      dataLines.clear();
      continue;
    }
    if (line.startsWith(':')) {
      continue;
    }
    final int colon = line.indexOf(':');
    final String field = colon == -1 ? line : line.substring(0, colon);
    String value = colon == -1 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) {
      value = value.substring(1);
    }
    switch (field) {
      case 'event':
        eventName = value;
      case 'data':
        dataLines.add(value);
      default:
      // `id`/`retry`/anything else: valid SSE, outside this app's contract.
    }
  }
  // The stream closed without a final blank line — the last, unterminated
  // block still gets dispatched rather than silently dropped.
  final SseEvent? tail = _dispatch(eventName, dataLines);
  if (tail != null) {
    yield tail;
  }
}

/// Null for a block that named no event and carried no data — comment-only or
/// empty input, which the spec says dispatches nothing.
SseEvent? _dispatch(String? eventName, List<String> dataLines) {
  if (eventName == null && dataLines.isEmpty) {
    return null;
  }
  return SseEvent(event: eventName ?? 'message', data: dataLines.join('\n'));
}
