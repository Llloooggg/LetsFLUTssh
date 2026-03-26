import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/connection/connection.dart';
import 'tab_model.dart';

/// State notifier for managing open tabs.
class TabNotifier extends Notifier<TabState> {
  static const _uuid = Uuid();

  @override
  TabState build() => const TabState();

  /// Open a new terminal tab for a connection.
  String addTerminalTab(Connection connection, {String? label}) {
    final id = _uuid.v4();
    final tab = TabEntry(
      id: id,
      label: label ?? connection.label,
      connection: connection,
      kind: TabKind.terminal,
    );
    state = state.copyWith(
      tabs: [...state.tabs, tab],
      activeIndex: state.tabs.length,
    );
    return id;
  }

  /// Open a new SFTP tab for a connection.
  String addSftpTab(Connection connection, {String? label}) {
    final id = _uuid.v4();
    final tab = TabEntry(
      id: id,
      label: label ?? '${connection.label} (SFTP)',
      connection: connection,
      kind: TabKind.sftp,
    );
    state = state.copyWith(
      tabs: [...state.tabs, tab],
      activeIndex: state.tabs.length,
    );
    return id;
  }

  /// Close a tab by id.
  void closeTab(String id) {
    final idx = state.tabs.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final newTabs = [...state.tabs]..removeAt(idx);
    var newActive = state.activeIndex;
    if (newActive >= newTabs.length) {
      newActive = newTabs.length - 1;
    }
    if (newActive < 0) newActive = -1;
    state = state.copyWith(tabs: newTabs, activeIndex: newActive);
  }

  /// Close all tabs except the one with the given id.
  void closeOthers(String id) {
    final tab = state.tabs.firstWhere((t) => t.id == id);
    state = state.copyWith(tabs: [tab], activeIndex: 0);
  }

  /// Close all tabs to the right of the given index.
  void closeToTheRight(int index) {
    if (index >= state.tabs.length - 1) return;
    final newTabs = state.tabs.sublist(0, index + 1);
    var newActive = state.activeIndex;
    if (newActive >= newTabs.length) {
      newActive = newTabs.length - 1;
    }
    state = state.copyWith(tabs: newTabs, activeIndex: newActive);
  }

  /// Close all tabs to the left of the given index.
  void closeToTheLeft(int index) {
    if (index <= 0) return;
    final newTabs = state.tabs.sublist(index);
    var newActive = state.activeIndex - index;
    if (newActive < 0) newActive = 0;
    state = state.copyWith(tabs: newTabs, activeIndex: newActive);
  }

  /// Select a tab by index.
  void selectTab(int index) {
    if (index >= 0 && index < state.tabs.length) {
      state = state.copyWith(activeIndex: index);
    }
  }

  /// Reorder tabs (for drag-to-reorder).
  void reorderTabs(int oldIndex, int newIndex) {
    final tabs = [...state.tabs];
    if (newIndex > oldIndex) newIndex--;
    final tab = tabs.removeAt(oldIndex);
    tabs.insert(newIndex, tab);

    var activeIdx = state.activeIndex;
    if (activeIdx == oldIndex) {
      activeIdx = newIndex;
    } else if (oldIndex < activeIdx && newIndex >= activeIdx) {
      activeIdx--;
    } else if (oldIndex > activeIdx && newIndex <= activeIdx) {
      activeIdx++;
    }
    state = state.copyWith(tabs: tabs, activeIndex: activeIdx);
  }

  /// Swap two tabs by index (for drag-and-drop reorder).
  void swapTabs(int idx1, int idx2) {
    if (idx1 == idx2) return;
    if (idx1 < 0 || idx2 < 0 || idx1 >= state.tabs.length || idx2 >= state.tabs.length) return;
    final tabs = [...state.tabs];
    final temp = tabs[idx1];
    tabs[idx1] = tabs[idx2];
    tabs[idx2] = temp;

    var activeIdx = state.activeIndex;
    if (activeIdx == idx1) {
      activeIdx = idx2;
    } else if (activeIdx == idx2) {
      activeIdx = idx1;
    }
    state = state.copyWith(tabs: tabs, activeIndex: activeIdx);
  }
}

/// Immutable tab state.
class TabState {
  final List<TabEntry> tabs;
  final int activeIndex;

  const TabState({this.tabs = const [], this.activeIndex = -1});

  TabEntry? get activeTab =>
      activeIndex >= 0 && activeIndex < tabs.length
          ? tabs[activeIndex]
          : null;

  TabState copyWith({List<TabEntry>? tabs, int? activeIndex}) {
    return TabState(
      tabs: tabs ?? this.tabs,
      activeIndex: activeIndex ?? this.activeIndex,
    );
  }
}

/// Riverpod provider for tab state.
final tabProvider = NotifierProvider<TabNotifier, TabState>(TabNotifier.new);
