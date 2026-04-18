import 'package:flutter/material.dart';

/// Shared Enter-key wiring for multi-field input forms.
///
/// Owns a fixed-length list of [FocusNode]s and returns the per-field
/// [TextInputAction] + `onSubmitted` callback that implement the
/// "Enter advances to the next field; Enter on the last field submits"
/// pattern used in every input dialog in the app.
///
/// Usage from a [StatefulWidget]:
///
/// ```dart
/// late final _chain = FormSubmitChain(length: 3, onSubmit: _submit);
///
/// @override
/// void dispose() {
///   _chain.dispose();
///   super.dispose();
/// }
///
/// @override
/// Widget build(BuildContext context) {
///   return Column(children: [
///     TextField(
///       focusNode: _chain.nodeAt(0),
///       textInputAction: _chain.actionAt(0),
///       onSubmitted: _chain.handlerAt(0),
///     ),
///     // …
///   ]);
/// }
/// ```
///
/// Rationale: Flutter [TextField]s intercept the Enter key before any
/// parent [CallbackShortcuts] can see it, so a dialog-level shortcut
/// cannot implement "Enter submits from any field". Each field must
/// wire `onSubmitted` individually. Centralising that wiring here
/// keeps dialogs short, makes the pattern discoverable, and prevents
/// per-dialog regressions (e.g. a field that silently fails to
/// advance focus because someone forgot to set [TextInputAction.next]).
class FormSubmitChain {
  final VoidCallback _onSubmit;
  final List<FocusNode> _nodes;

  FormSubmitChain({required int length, required VoidCallback onSubmit})
    : assert(length > 0, 'FormSubmitChain needs at least one field'),
      _onSubmit = onSubmit,
      _nodes = List.generate(length, (_) => FocusNode());

  /// Focus node for the field at [index].
  FocusNode nodeAt(int index) => _nodes[index];

  /// `TextInputAction.next` for non-last fields, `done` for the last.
  TextInputAction actionAt(int index) =>
      index == _nodes.length - 1 ? TextInputAction.done : TextInputAction.next;

  /// `onSubmitted` callback that advances focus for non-last fields
  /// and triggers `onSubmit` for the last field.
  ValueChanged<String> handlerAt(int index) {
    return (_) {
      if (index == _nodes.length - 1) {
        _onSubmit();
      } else {
        _nodes[index + 1].requestFocus();
      }
    };
  }

  /// Length of the chain (number of fields).
  int get length => _nodes.length;

  /// Dispose every focus node. Call from the owning widget's
  /// `dispose()`.
  void dispose() {
    for (final n in _nodes) {
      n.dispose();
    }
  }
}
