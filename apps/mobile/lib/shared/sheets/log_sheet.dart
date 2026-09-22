/// `H.openLog(kind)` — one observation, recorded in a sheet.
///
/// The prototype opens a dialog with the amount, the time and a save button; the
/// v02 journal screen is a grid of kinds rather than a form with a dropdown, so
/// the kind is chosen before the sheet opens and the sheet is about one thing.
///
/// ## Everything the old editor guaranteed, kept
///
/// `journal_editor.dart` held three behaviours that are not decoration and they
/// are all here:
///
///   * **the draft survives a failed write.** A save that could not be confirmed
///     leaves the form exactly as it was and says so — the owner types a weight
///     once;
///   * **the form clears only on acknowledgement.** `_save` clears after the
///     server answered, never on the tap;
///   * **validation is `LogDraft.validate`'s**, so the phone and the endpoint
///     agree about what a valid entry is.
///
/// The sheet is opened through [showAppSheet] — root navigator, over the tab bar
/// — which `sheet_layering_test.dart` enforces for every sheet in the app.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/core/logging.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_scale.dart';
import 'package:healthee/data/journal/journal_repository.dart';
import 'package:healthee/data/journal/log_draft.dart';
import 'package:healthee/data/journal/log_kind.dart';
import 'package:healthee/data/today_repository.dart';
import 'package:healthee/shared/sheets/app_sheet.dart';
import 'package:healthee/shared/v02/controls.dart';
import 'package:solar_icons/solar_icons.dart';

/// Opens the log for [kind].
void showLogSheet(
  BuildContext context, {
  required JournalRepository repository,
  required LogKind kind,
}) {
  unawaited(
    showAppSheet<void>(
      context: context,
      builder: (context) => LogSheet(repository: repository, kind: kind),
    ),
  );
}

/// Opens the fast control — start or end, whichever the server's state allows.
void showFastSheet(
  BuildContext context, {
  required JournalRepository repository,
  required bool open,
}) {
  unawaited(
    showAppSheet<void>(
      context: context,
      builder: (context) => LogSheet(
        repository: repository,
        kind: null,
        fastOpen: open,
      ),
    ),
  );
}

/// One observation's form. [kind] of null is the fast.
class LogSheet extends ConsumerStatefulWidget {
  /// [fastOpen] is only read when [kind] is null.
  const LogSheet({
    required this.repository,
    required this.kind,
    this.fastOpen = false,
    super.key,
  });

  /// Where the write goes.
  final JournalRepository repository;

  /// What is being recorded. Null is the fast.
  final LogKind? kind;

  /// Whether a fast is already running.
  final bool fastOpen;

  @override
  ConsumerState<LogSheet> createState() => _LogSheetState();
}

class _LogSheetState extends ConsumerState<LogSheet> {
  final TextEditingController _value = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  DateTime? _at;
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _value.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final kind = widget.kind;
    return Padding(
      padding: EdgeInsets.only(bottom: sheetBottomInset(context)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.bg,
          border: Border(top: BorderSide(color: colors.line, width: hairline)),
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(Radii.sheet),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Insets.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  kind == null
                      ? (widget.fastOpen ? 'End your fast' : 'Start a fast')
                      : 'Log ${kind.label.toLowerCase()}',
                  style: TypeScale.detailTitle.copyWith(color: colors.ink),
                ),
                const SizedBox(height: Insets.lg),
                if (kind != null) ..._fields(context, kind),
                if (_message case final String message)
                  Semantics(
                    liveRegion: true,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: Insets.md),
                      child: Text(
                        message,
                        style: TypeScale.small.copyWith(color: colors.ink2),
                      ),
                    ),
                  ),
                ActionButton(
                  full: true,
                  label: _busy
                      ? 'Saving…'
                      : kind == null
                      ? (widget.fastOpen ? 'End fast' : 'Start fast')
                      : 'Save entry',
                  onPressed: _busy ? null : () => unawaited(_submit()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _fields(BuildContext context, LogKind kind) {
    final colors = context.colors;
    return <Widget>[
      TextField(
        controller: _value,
        enabled: !_busy,
        style: TypeScale.inputText.copyWith(color: colors.ink),
        keyboardType: kind.needsName
            ? TextInputType.text
            : const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: kind.needsName ? 'Description' : 'Amount',
          suffixText: kind.unit,
        ),
      ),
      const SizedBox(height: Insets.md),
      TextField(
        controller: _notes,
        enabled: !_busy,
        maxLength: 2000,
        style: TypeScale.inputText.copyWith(color: colors.ink),
        decoration: const InputDecoration(labelText: 'Notes (optional)'),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextLink(
          label: _at == null ? 'When: now' : 'When: ${_at!.toLocal()}',
          icon: SolarIconsOutline.clockCircle,
          onPressed: _busy ? null : () => unawaited(_pickTime()),
        ),
      ),
      if (kind.isDuration)
        Padding(
          padding: const EdgeInsets.only(bottom: Insets.md),
          child: Text(
            'The selected time is when the session ended.',
            style: TypeScale.tinyLabel.copyWith(color: colors.ink2),
          ),
        ),
      const SizedBox(height: Insets.md),
    ];
  }

  Future<void> _pickTime() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: _at ?? now,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (day == null || !mounted) {
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_at ?? now),
    );
    if (time == null || !mounted) {
      return;
    }
    setState(
      () => _at = DateTime(day.year, day.month, day.day, time.hour, time.minute),
    );
  }

  Future<void> _submit() async {
    final kind = widget.kind;
    if (kind == null) {
      await _write(() => widget.repository.fasting(end: widget.fastOpen));
      return;
    }
    final draft = LogDraft(
      kind: kind,
      at: _at ?? DateTime.now(),
      amount: kind.needsName ? null : double.tryParse(_value.text.trim()),
      name: kind.needsName ? _value.text : null,
      notes: _notes.text,
    );
    final problem = draft.validate(DateTime.now());
    if (problem != null) {
      setState(() => _message = problem);
      return;
    }
    await _write(() => widget.repository.save(draft), clearForm: true);
  }

  Future<void> _write(
    Future<String?> Function() operation, {
    bool clearForm = false,
  }) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final notice = await operation();
      if (!mounted) {
        return;
      }
      ref.invalidate(journalFeedProvider);
      ref.invalidate(todaySnapshotProvider);
      setState(() {
        _message = notice ?? 'Saved.';
        if (clearForm) {
          _value.clear();
          _notes.clear();
          _at = null;
        }
      });
    } on Exception catch (error, stack) {
      AppLog.failure('journal', 'saving an observation', error, stack);
      if (mounted) {
        setState(
          () => _message =
              'Save could not be confirmed. Refresh recent entries before '
              'retrying. Your form is still here.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}
