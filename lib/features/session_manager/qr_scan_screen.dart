import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/session/qr_codec.dart';
import '../../theme/app_theme.dart';
import '../../utils/logger.dart';

/// QR code scanner screen for importing sessions.
///
/// Uses [MobileScanner] to detect QR codes. When a valid LetsFLUTssh
/// QR payload is detected, shows a preview and lets the user confirm import.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  /// Show the scanner and return [QrImportData] if a valid QR was scanned,
  /// or null if cancelled.
  static Future<QrImportData?> show(BuildContext context) {
    return Navigator.of(context).push<QrImportData>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
  }

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: [BarcodeFormat.qrCode],
  );

  bool _processing = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR Code'),
        actions: [
          IconButton(
            onPressed: () => _controller.toggleTorch(),
            icon: ValueListenableBuilder(
              valueListenable: _controller,
              builder: (context, state, _) {
                return Icon(
                  state.torchState == TorchState.on
                      ? Icons.flash_on
                      : Icons.flash_off,
                );
              },
            ),
            tooltip: 'Toggle flash',
          ),
          IconButton(
            onPressed: () => _controller.switchCamera(),
            icon: const Icon(Icons.cameraswitch),
            tooltip: 'Switch camera',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.videocam_off, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        _cameraErrorMessage(error),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          // Status bar
          Container(
            padding: const EdgeInsets.all(16),
            color: theme.colorScheme.surfaceContainerLow,
            child: Column(
              children: [
                if (_processing)
                  const CircularProgressIndicator()
                else if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(color: AppTheme.disconnectedColor(theme.brightness)),
                    textAlign: TextAlign.center,
                  )
                else
                  Text(
                    'Point camera at a LetsFLUTssh QR code',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onDetect(BarcodeCapture capture) {
    if (_processing) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;

      final data = decodeSessionsFromQr(raw);
      if (data == null) {
        setState(() => _error = 'Not a valid LetsFLUTssh QR code');
        continue;
      }

      if (data.sessions.isEmpty) {
        setState(() => _error = 'QR code contains no sessions');
        continue;
      }

      setState(() => _processing = true);
      AppLogger.instance.log(
        'QR scanned: ${data.sessions.length} session(s)',
        name: 'QrScan',
      );
      _showPreview(data);
      return;
    }
  }

  Future<void> _showPreview(QrImportData data) async {
    final confirmed = await showDialog<bool>(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      builder: (ctx) => AlertDialog(
        title: const Text('Import Sessions'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Found ${data.sessions.length} session(s):'),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: data.sessions.length,
                itemBuilder: (ctx, i) {
                  final s = data.sessions[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.computer, size: 18),
                    title: Text(
                      s.label.isNotEmpty ? s.label : '${s.user}@${s.host}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: s.group.isNotEmpty
                        ? Text(s.group, style: const TextStyle(fontSize: 11))
                        : null,
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  );
                },
              ),
            ),
            if (data.emptyGroups.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${data.emptyGroups.length} folder(s)',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 14),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Sessions will be imported without credentials.\n'
                      'You will need to fill in passwords/keys.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Import'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      Navigator.of(context).pop(data);
    } else {
      setState(() {
        _processing = false;
        _error = null;
      });
    }
  }

  String _cameraErrorMessage(MobileScannerException error) {
    switch (error.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        return 'Camera permission denied.\nGo to Settings to allow camera access.';
      case MobileScannerErrorCode.unsupported:
        return 'Camera is not supported on this device.';
      default:
        return 'Camera error: ${error.errorDetails?.message ?? 'unknown'}';
    }
  }

  @override
  Future<void> dispose() async {
    super.dispose();
    await _controller.dispose();
  }
}
