/// Enroll this phone from the administrator's QR — `docs/QR_ENROLLMENT.md`.
///
/// Two ways in, one confirmation. The owner scans the code (or pastes the link
/// printed under it), and before anything is sent the card names the server the
/// link points at and asks. A QR is an instruction from whoever printed it, and
/// this one decides where the phone will send health data: a code from somebody
/// else's server must be a thing the owner declines, not a thing that happens.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_scale_forms.dart';
import 'package:healthee/data/api/signin_failure.dart';
import 'package:healthee/data/auth/enrollment_link.dart';
import 'package:healthee/features/signin/enrollment_scanner_screen.dart';
import 'package:healthee/shared/v02/buttons.dart';
import 'package:healthee/shared/v02/fields.dart';
import 'package:healthee/shared/v02/settings_page.dart';
import 'package:healthee/shared/v02/surfaces.dart';

/// Opens the camera and returns what it read, or null when the owner backed out.
typedef EnrollmentScan = Future<String?> Function(BuildContext context);

Future<String?> _scanWithCamera(BuildContext context) =>
    Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => const EnrollmentScannerScreen(),
      ),
    );

/// The enrollment card on the account screen.
class EnrollmentEntry extends StatefulWidget {
  /// [onEnroll] receives a link the owner has confirmed.
  const EnrollmentEntry({
    required this.enabled,
    required this.onEnroll,
    required this.onEdited,
    this.scan = _scanWithCamera,
    super.key,
  });

  /// False while a sign-in is running.
  final bool enabled;

  /// Redeem [EnrollmentLink] — called only after the owner confirmed its host.
  final void Function(EnrollmentLink link) onEnroll;

  /// Clears a stale failure when the owner starts again.
  final VoidCallback onEdited;

  /// The camera. Injected so a test can stand in for it.
  final EnrollmentScan scan;

  /// The card's title.
  static const String title = 'Enroll with a QR code';

  @override
  State<EnrollmentEntry> createState() => _EnrollmentEntryState();
}

class _EnrollmentEntryState extends State<EnrollmentEntry> {
  final TextEditingController _link = TextEditingController();
  EnrollmentLink? _pending;
  ServerSignInFailure? _problem;

  @override
  void dispose() {
    // It holds a one-time code; drop it as early as the widget allows.
    _link
      ..clear()
      ..dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final raw = await widget.scan(context);
    if (raw != null && mounted) {
      _consider(raw);
    }
  }

  void _consider(String raw) {
    widget.onEdited();
    try {
      final link = EnrollmentLink.parse(raw);
      setState(() {
        _pending = link;
        _problem = null;
      });
    } on ServerSignInException catch (error) {
      setState(() {
        _pending = null;
        _problem = error.failure;
      });
    }
  }

  void _confirm(EnrollmentLink link) {
    setState(() => _pending = null);
    _link.clear();
    widget.onEnroll(link);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final pending = _pending;
    return PlainCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            EnrollmentEntry.title,
            style: FormType.heading3.copyWith(color: colors.ink),
          ),
          const SizedBox(height: SectionGap.height),
          if (pending == null) ..._entry() else ..._confirmation(pending),
          if (_problem case final ServerSignInFailure problem) ...<Widget>[
            const SizedBox(height: SectionGap.height),
            Text(
              problem.headline,
              style: FormType.heading3.copyWith(color: colors.ink),
            ),
            SmallProse(problem.remedy),
          ],
        ],
      ),
    );
  }

  List<Widget> _entry() => <Widget>[
    const SmallProse(
      'Run `healthee.db.enroll issue` on your server and scan the code it '
      'prints. No password: the code works once, for a few minutes, and this '
      'phone gets its own key that can be revoked on the server.',
    ),
    const SizedBox(height: SectionGap.height),
    HButton(
      label: 'Scan the QR code',
      onPressed: widget.enabled ? () => unawaited(_scan()) : null,
    ),
    const SizedBox(height: SectionGap.height),
    HField(
      label: 'Or paste the enrollment link',
      hint: 'healthee://enroll?…',
      child: HTextField(
        controller: _link,
        enabled: widget.enabled,
        keyboardType: TextInputType.url,
        onSubmitted: _consider,
        onChanged: (_) => widget.onEdited(),
      ),
    ),
    HButton(
      label: 'Use this link',
      kind: HButtonKind.secondary,
      onPressed: widget.enabled ? () => _consider(_link.text) : null,
    ),
  ];

  List<Widget> _confirmation(EnrollmentLink link) => <Widget>[
    SmallProse(
      'Connect this phone to ${link.server.host}? Only continue if you issued '
      'this code yourself, on your own server. It replaces the server this '
      'phone uses now; the strap pairing and any unsent readings are kept and '
      'upload to the new one.',
    ),
    const SizedBox(height: SectionGap.height),
    HButton(
      label: 'Connect to ${link.server.host}',
      onPressed: widget.enabled ? () => _confirm(link) : null,
    ),
    const SizedBox(height: SectionGap.height),
    HLinkButton(
      label: 'Cancel',
      onPressed: () => setState(() => _pending = null),
    ),
  ];
}
