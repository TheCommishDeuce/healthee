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

/// Weight and its observation time: the two fields the server actually stores.
class WeightLogSheet extends ConsumerStatefulWidget {
  const WeightLogSheet({required this.repository, super.key});

  final JournalRepository repository;

  @override
  ConsumerState<WeightLogSheet> createState() => _WeightLogSheetState();
}

class _WeightLogSheetState extends ConsumerState<WeightLogSheet> {
  final TextEditingController _value = TextEditingController();
  DateTime? _at;
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: sheetBottomInset(context)),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.bg,
        border: Border(
          top: BorderSide(color: context.colors.line, width: hairline),
        ),
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
            children: _fields(context),
          ),
        ),
      ),
    ),
  );

  List<Widget> _fields(BuildContext context) => [
    Text(
      'Log weight',
      style: TypeScale.detailTitle.copyWith(color: context.colors.ink),
    ),
    const SizedBox(height: Insets.lg),
    TextField(
      controller: _value,
      enabled: !_busy,
      style: TypeScale.inputText.copyWith(color: context.colors.ink),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(labelText: 'Weight', suffixText: 'kg'),
    ),
    Align(
      alignment: Alignment.centerLeft,
      child: TextLink(
        label: _at == null ? 'When: now' : 'When: ${_at!.toLocal()}',
        icon: SolarIconsOutline.clockCircle,
        onPressed: _busy ? null : () => unawaited(_pickTime()),
      ),
    ),
    const SizedBox(height: Insets.md),
    if (_message case final String message)
      Semantics(
        liveRegion: true,
        child: Padding(
          padding: const EdgeInsets.only(bottom: Insets.md),
          child: Text(
            message,
            style: TypeScale.small.copyWith(color: context.colors.ink2),
          ),
        ),
      ),
    ActionButton(
      full: true,
      label: _busy ? 'Saving…' : 'Save entry',
      onPressed: _busy ? null : () => unawaited(_submit()),
    ),
  ];

  Future<void> _pickTime() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: _at ?? now,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_at ?? now),
    );
    if (time == null || !mounted) return;
    setState(
      () =>
          _at = DateTime(day.year, day.month, day.day, time.hour, time.minute),
    );
  }

  Future<void> _submit() async {
    if (_busy) return;
    final draft = LogDraft(
      kind: LogKind.weight,
      at: _at ?? DateTime.now(),
      amount: double.tryParse(_value.text.trim()),
    );
    final problem = draft.validate(DateTime.now());
    if (problem != null) {
      setState(() => _message = problem);
      return;
    }
    await _save(draft);
  }

  Future<void> _save(LogDraft draft) async {
    setState(() {
      _busy = true;
      _message = null;
      // Weight is upserted by (owner, timestamp). A retry keeps that identity.
      _at = draft.at;
    });
    try {
      final notice = await widget.repository.save(draft);
      if (!mounted) return;
      ref.invalidate(journalFeedProvider);
      ref.invalidate(todaySnapshotProvider);
      setState(() {
        _message = notice ?? 'Saved.';
        _value.clear();
        _at = null;
      });
    } on Exception catch (error, stack) {
      AppLog.failure('weight', 'saving a weigh-in', error, stack);
      if (mounted) {
        setState(
          () => _message =
              'Save could not be confirmed. Check weight history '
              'before retrying. Your form is still here.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
