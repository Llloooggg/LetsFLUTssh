import 'package:flutter/foundation.dart';

import '../../core/transfer/transfer_task.dart';
import 'column_widths.dart';

/// Sort column options for the transfer history table.
enum TransferSortColumn { name, local, remote, size, time }

/// Headless state for [TransferPanel]. Owns sort, column widths, panel
/// height, and expand / auto-expand behaviour so the widget class stays
/// a thin renderer wired through [AnimatedBuilder].
///
/// Same `ChangeNotifier` pattern as [FilePaneController] and
/// [SessionPanelController] — widget-local state, never shared across
/// widgets, tied to a single panel's lifecycle.
class TransferPanelController extends ChangeNotifier {
  // ---- Constraints --------------------------------------------------

  /// Bounds for [resizePanelHeightBy] — clamps the resizer drag so the
  /// panel cannot collapse below a legible height or swallow the whole
  /// window.
  static const double panelHeightMin = 80;
  static const double panelHeightMax = 500;

  /// Bounds for path-column drags (local / remote).
  static const double pathColMin = 60;
  static const double pathColMax = 300;

  /// Bounds for the size column — narrower range because the content is
  /// short ("1.2 MB").
  static const double sizeColMin = 40;
  static const double sizeColMax = 150;

  /// Bounds for the time column — fits "10:03:15" down to "yesterday".
  static const double timeColMin = 60;
  static const double timeColMax = 200;

  /// Name column is not user-resizable. Narrower than the legacy 150 so
  /// the transfer-queue header visually matches the SFTP tab layout
  /// where the Name cell is tighter — the user complaint was "name
  /// слишком широкий". Local / Remote are wider because they show
  /// full paths.
  static const double nameColWidth = 110;

  // ---- State --------------------------------------------------------

  bool _expanded = false;
  bool _wasRunning = false;
  double _panelHeight = 200;

  double _localColWidth = 110;
  double _remoteColWidth = 110;
  // Size and Time share defaults with FilePane so the two tables stay
  // visually aligned — see [FileBrowserColumns].
  double _sizeColWidth = FileBrowserColumns.size;
  double _timeColWidth = FileBrowserColumns.modifiedOrTime;

  TransferSortColumn _sortColumn = TransferSortColumn.time;
  bool _sortAscending = false;

  bool get expanded => _expanded;
  double get panelHeight => _panelHeight;
  double get localColWidth => _localColWidth;
  double get remoteColWidth => _remoteColWidth;
  double get sizeColWidth => _sizeColWidth;
  double get timeColWidth => _timeColWidth;
  TransferSortColumn get sortColumn => _sortColumn;
  bool get sortAscending => _sortAscending;

  // ---- Expand -------------------------------------------------------

  void toggleExpanded() {
    _expanded = !_expanded;
    notifyListeners();
  }

  void setExpanded(bool value) {
    if (_expanded == value) return;
    _expanded = value;
    notifyListeners();
  }

  /// Called from [build] whenever the live `isRunning` flag changes.
  /// Expands the panel on the `false → true` edge so the user never
  /// misses a transfer they just kicked off. Idempotent — repeated
  /// calls with the same value are a no-op (no listener churn).
  void syncAutoExpand(bool isRunning) {
    final shouldAutoExpand = isRunning && !_wasRunning && !_expanded;
    _wasRunning = isRunning;
    if (shouldAutoExpand) {
      _expanded = true;
      notifyListeners();
    }
  }

  // ---- Resize -------------------------------------------------------

  void resizePanelHeightBy(double dy) {
    final next = (_panelHeight - dy).clamp(panelHeightMin, panelHeightMax);
    if (next == _panelHeight) return;
    _panelHeight = next;
    notifyListeners();
  }

  void resizeLocalColBy(double dx) {
    final next = (_localColWidth - dx).clamp(pathColMin, pathColMax);
    if (next == _localColWidth) return;
    _localColWidth = next;
    notifyListeners();
  }

  void resizeRemoteColBy(double dx) {
    final next = (_remoteColWidth - dx).clamp(pathColMin, pathColMax);
    if (next == _remoteColWidth) return;
    _remoteColWidth = next;
    notifyListeners();
  }

  void resizeSizeColBy(double dx) {
    final next = (_sizeColWidth - dx).clamp(sizeColMin, sizeColMax);
    if (next == _sizeColWidth) return;
    _sizeColWidth = next;
    notifyListeners();
  }

  void resizeTimeColBy(double dx) {
    final next = (_timeColWidth - dx).clamp(timeColMin, timeColMax);
    if (next == _timeColWidth) return;
    _timeColWidth = next;
    notifyListeners();
  }

  // ---- Sort ---------------------------------------------------------

  /// Click-cycle: same column toggles direction; new column resets to
  /// ascending (the idiomatic file-manager pattern).
  void setSort(TransferSortColumn column) {
    if (_sortColumn == column) {
      _sortAscending = !_sortAscending;
    } else {
      _sortColumn = column;
      _sortAscending = true;
    }
    notifyListeners();
  }

  /// Pure comparator — returns a new list sorted by the current column
  /// + direction. Doesn't mutate the input and doesn't touch any state,
  /// so unit tests can drive this directly without a widget tree.
  List<HistoryEntry> sorted(List<HistoryEntry> history) {
    final out = List<HistoryEntry>.from(history);
    out.sort((a, b) {
      final cmp = switch (_sortColumn) {
        TransferSortColumn.name => a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        ),
        TransferSortColumn.local => _localPath(a).compareTo(_localPath(b)),
        TransferSortColumn.remote => _remotePath(a).compareTo(_remotePath(b)),
        TransferSortColumn.size => a.sizeBytes.compareTo(b.sizeBytes),
        TransferSortColumn.time =>
          (a.endedAt ?? a.startedAt ?? a.createdAt).compareTo(
            b.endedAt ?? b.startedAt ?? b.createdAt,
          ),
      };
      return _sortAscending ? cmp : -cmp;
    });
    return out;
  }

  static String _localPath(HistoryEntry e) =>
      e.direction == TransferDirection.upload ? e.sourcePath : e.targetPath;

  static String _remotePath(HistoryEntry e) =>
      e.direction == TransferDirection.upload ? e.targetPath : e.sourcePath;
}
