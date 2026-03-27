import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Direction of a split.
enum SplitDirection { horizontal, vertical }

/// A node in the recursive split tree.
///
/// Either a [LeafNode] (single terminal pane) or a [BranchNode] (two children).
sealed class SplitNode {
  final String id;
  SplitNode({String? id}) : id = id ?? _uuid.v4();
}

/// A leaf node — holds a single terminal pane.
class LeafNode extends SplitNode {
  LeafNode({super.id});
}

/// A branch node — two children split in a direction with a ratio.
class BranchNode extends SplitNode {
  final SplitDirection direction;
  final double ratio;
  final SplitNode first;
  final SplitNode second;

  BranchNode({
    super.id,
    required this.direction,
    this.ratio = 0.5,
    required this.first,
    required this.second,
  });
}

/// Finds and replaces a node in the tree. Returns new root.
SplitNode replaceNode(SplitNode root, String targetId, SplitNode replacement) {
  if (root.id == targetId) return replacement;
  if (root is BranchNode) {
    return BranchNode(
      id: root.id,
      direction: root.direction,
      ratio: root.ratio,
      first: replaceNode(root.first, targetId, replacement),
      second: replaceNode(root.second, targetId, replacement),
    );
  }
  return root;
}

/// Removes a leaf from the tree. Returns the sibling (promoted up).
/// If root is the target leaf, returns null.
SplitNode? removeNode(SplitNode root, String targetId) {
  if (root.id == targetId) return null;
  if (root is BranchNode) {
    if (root.first.id == targetId) return root.second;
    if (root.second.id == targetId) return root.first;
    final newFirst = removeNode(root.first, targetId);
    if (newFirst != null && !identical(newFirst, root.first)) {
      return BranchNode(
        id: root.id,
        direction: root.direction,
        ratio: root.ratio,
        first: newFirst,
        second: root.second,
      );
    }
    final newSecond = removeNode(root.second, targetId);
    if (newSecond != null && !identical(newSecond, root.second)) {
      return BranchNode(
        id: root.id,
        direction: root.direction,
        ratio: root.ratio,
        first: root.first,
        second: newSecond,
      );
    }
  }
  return root;
}

/// Collects all leaf node IDs.
List<String> collectLeafIds(SplitNode node) {
  if (node is LeafNode) return [node.id];
  if (node is BranchNode) {
    return [...collectLeafIds(node.first), ...collectLeafIds(node.second)];
  }
  return [];
}
