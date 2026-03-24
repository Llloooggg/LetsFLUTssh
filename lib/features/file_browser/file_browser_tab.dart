import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/connection/connection.dart';
import '../../core/sftp/file_system.dart';
import '../../core/sftp/sftp_client.dart';
import '../../core/sftp/sftp_models.dart';
import '../../core/transfer/transfer_task.dart';
import '../../providers/transfer_provider.dart';
import 'file_browser_controller.dart';
import 'file_pane.dart';
import 'transfer_panel.dart';

/// Dual-pane SFTP file browser tab.
class FileBrowserTab extends ConsumerStatefulWidget {
  final Connection connection;

  const FileBrowserTab({
    super.key,
    required this.connection,
  });

  @override
  ConsumerState<FileBrowserTab> createState() => _FileBrowserTabState();
}

class _FileBrowserTabState extends ConsumerState<FileBrowserTab> {
  FilePaneController? _localCtrl;
  FilePaneController? _remoteCtrl;
  SFTPService? _sftpService;
  bool _initializing = true;
  String? _error;
  double _splitRatio = 0.5;

  @override
  void initState() {
    super.initState();
    _initSftp();
  }

  @override
  void dispose() {
    _localCtrl?.dispose();
    _remoteCtrl?.dispose();
    _sftpService?.close();
    super.dispose();
  }

  Future<void> _initSftp() async {
    try {
      final sshClient = widget.connection.sshConnection?.client;
      if (sshClient == null) {
        setState(() {
          _error = 'SSH connection not available';
          _initializing = false;
        });
        return;
      }

      _sftpService = await SFTPService.fromSSHClient(sshClient);

      _localCtrl = FilePaneController(fs: LocalFS(), label: 'Local');
      _remoteCtrl = FilePaneController(fs: RemoteFS(_sftpService!), label: 'Remote');

      await Future.wait([_localCtrl!.init(), _remoteCtrl!.init()]);

      if (mounted) {
        setState(() => _initializing = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to initialize SFTP: $e';
          _initializing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Initializing SFTP...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
            const SizedBox(height: 8),
            Text(_error!),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () {
                setState(() {
                  _initializing = true;
                  _error = null;
                });
                _initSftp();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Dual-pane file browser with resizable split
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth;
              final leftWidth = (_splitRatio * maxWidth)
                  .clamp(100.0, maxWidth - 100);

              return Row(
                children: [
                  // Local pane
                  SizedBox(
                    width: leftWidth,
                    child: FilePane(
                      controller: _localCtrl!,
                      onTransfer: (entry) => _upload(entry),
                      onTransferMultiple: (entries) {
                        for (final e in entries) {
                          _upload(e);
                        }
                      },
                    ),
                  ),
                  // Draggable divider
                  MouseRegion(
                    cursor: SystemMouseCursors.resizeColumn,
                    child: GestureDetector(
                      onHorizontalDragUpdate: (d) {
                        setState(() {
                          _splitRatio = ((_splitRatio * maxWidth + d.delta.dx) / maxWidth)
                              .clamp(0.2, 0.8);
                        });
                      },
                      child: Container(
                        width: 4,
                        color: Theme.of(context).dividerColor,
                      ),
                    ),
                  ),
                  // Remote pane
                  Expanded(
                    child: FilePane(
                      controller: _remoteCtrl!,
                      onTransfer: (entry) => _download(entry),
                      onTransferMultiple: (entries) {
                        for (final e in entries) {
                          _download(e);
                        }
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        // Transfer panel
        const TransferPanel(),
      ],
    );
  }

  void _upload(FileEntry entry) {
    if (_sftpService == null) return;
    final manager = ref.read(transferManagerProvider);
    final remotePath = p.posix.join(
      _remoteCtrl!.currentPath,
      entry.name,
    );
    final sftp = _sftpService!;

    manager.enqueue(TransferTask(
      name: entry.isDir ? '${entry.name}/' : entry.name,
      direction: TransferDirection.upload,
      sourcePath: entry.path,
      targetPath: remotePath,
      run: (update) async {
        update(0, 'Starting upload...');
        if (entry.isDir) {
          await sftp.uploadDir(entry.path, remotePath, (progress) {
            update(progress.percent, '${progress.doneBytes}/${progress.totalBytes} files');
          });
        } else {
          await sftp.upload(entry.path, remotePath, (progress) {
            update(progress.percent, '${progress.doneBytes}/${progress.totalBytes}');
          });
        }
        _remoteCtrl?.refresh();
      },
    ));
  }

  void _download(FileEntry entry) {
    if (_sftpService == null) return;
    final manager = ref.read(transferManagerProvider);
    final localPath = p.join(
      _localCtrl!.currentPath,
      entry.name,
    );
    final sftp = _sftpService!;

    manager.enqueue(TransferTask(
      name: entry.isDir ? '${entry.name}/' : entry.name,
      direction: TransferDirection.download,
      sourcePath: entry.path,
      targetPath: localPath,
      run: (update) async {
        update(0, 'Starting download...');
        if (entry.isDir) {
          await sftp.downloadDir(entry.path, localPath, (progress) {
            update(progress.percent, '${progress.doneBytes}/${progress.totalBytes} files');
          });
        } else {
          await sftp.download(entry.path, localPath, (progress) {
            update(progress.percent, '${progress.doneBytes}/${progress.totalBytes}');
          });
        }
        _localCtrl?.refresh();
      },
    ));
  }
}
