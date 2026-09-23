/// The camera, for one purpose: reading the enrollment QR.
///
/// Returns the first QR payload that looks like a Healthee enrollment link and
/// closes. It decides nothing else: parsing, the host confirmation and the
/// redemption all happen back on the account screen (`EnrollmentEntry`), so the
/// only code that cannot be exercised without a camera is this thin frame.
library;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// The QR scanner. Pops with the scanned link, or with nothing on back.
class EnrollmentScannerScreen extends StatefulWidget {
  /// A full-screen scanner.
  const EnrollmentScannerScreen({super.key});

  @override
  State<EnrollmentScannerScreen> createState() =>
      _EnrollmentScannerScreenState();
}

class _EnrollmentScannerScreenState extends State<EnrollmentScannerScreen> {
  final MobileScannerController _camera = MobileScannerController(
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
  );
  bool _done = false;

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) {
      return;
    }
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.startsWith('healthee://')) {
        _done = true;
        Navigator.of(context).pop(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan the enrollment code')),
      body: MobileScanner(controller: _camera, onDetect: _onDetect),
    );
  }
}
