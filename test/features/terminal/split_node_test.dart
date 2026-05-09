import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/features/terminal/split_node.dart';

void main() {
  group('LeafNode', () {
    test('creates with auto-generated id', () {
      final leaf = LeafNode();
      expect(leaf.id, isNotEmpty);
    });

    test('creates with explicit id', () {
      final leaf = LeafNode(id: 'leaf-1');
      expect(leaf.id, 'leaf-1');
    });

    test('two nodes get different ids', () {
      final a = LeafNode();
      final b = LeafNode();
      expect(a.id, isNot(b.id));
    });
  });

  group('BranchNode', () {
    test('creates with required fields', () {
      final first = LeafNode(id: 'a');
      final second = LeafNode(id: 'b');
      final branch = BranchNode(
        direction: SplitDirection.horizontal,
        first: first,
        second: second,
      );
      expect(branch.direction, SplitDirection.horizontal);
      expect(branch.ratio, 0.5);
      expect(branch.first, first);
      expect(branch.second, second);
    });

    test('creates with explicit id and ratio', () {
      final branch = BranchNode(
        id: 'branch-1',
        direction: SplitDirection.vertical,
        ratio: 0.3,
        first: LeafNode(),
        second: LeafNode(),
      );
      expect(branch.id, 'branch-1');
      expect(branch.ratio, 0.3);
      expect(branch.direction, SplitDirection.vertical);
    });

    test('fields are immutable — new node created for changes', () {
      final branch = BranchNode(
        direction: SplitDirection.horizontal,
        ratio: 0.5,
        first: LeafNode(id: 'a'),
        second: LeafNode(id: 'b'),
      );

      // Update via new BranchNode (immutable pattern)
      final updated = BranchNode(
        id: branch.id,
        direction: SplitDirection.vertical,
        ratio: 0.7,
        first: LeafNode(id: 'c'),
        second: branch.second,
      );
      expect(updated.ratio, 0.7);
      expect(updated.direction, SplitDirection.vertical);
      expect(updated.first.id, 'c');
      // Original unchanged
      expect(branch.ratio, 0.5);
      expect(branch.direction, SplitDirection.horizontal);
      expect(branch.first.id, 'a');
    });
  });

  group('replaceNode', () {
    test('replaces root leaf', () {
      final root = LeafNode(id: 'root');
      final replacement = LeafNode(id: 'new');
      final result = replaceNode(root, 'root', replacement);
      expect(result.id, 'new');
    });

    test('replaces first child of branch', () {
      final first = LeafNode(id: 'a');
      final second = LeafNode(id: 'b');
      final root = BranchNode(
        id: 'branch',
        direction: SplitDirection.horizontal,
        first: first,
        second: second,
      );
      final replacement = LeafNode(id: 'new-a');
      final result = replaceNode(root, 'a', replacement) as BranchNode;
      expect(result.id, 'branch');
      expect(result.first.id, 'new-a');
      expect(result.second.id, 'b');
    });

    test('replaces second child of branch', () {
      final root = BranchNode(
        id: 'branch',
        direction: SplitDirection.vertical,
        first: LeafNode(id: 'a'),
        second: LeafNode(id: 'b'),
      );
      final replacement = LeafNode(id: 'new-b');
      final result = replaceNode(root, 'b', replacement) as BranchNode;
      expect(result.first.id, 'a');
      expect(result.second.id, 'new-b');
    });

    test('replaces deeply nested node', () {
      // Build tree:  branch1(branch2(leaf-a, leaf-b), leaf-c)
      final root = BranchNode(
        id: 'branch1',
        direction: SplitDirection.horizontal,
        first: BranchNode(
          id: 'branch2',
          direction: SplitDirection.vertical,
          first: LeafNode(id: 'leaf-a'),
          second: LeafNode(id: 'leaf-b'),
        ),
        second: LeafNode(id: 'leaf-c'),
      );

      final replacement = LeafNode(id: 'leaf-new');
      final result = replaceNode(root, 'leaf-b', replacement) as BranchNode;

      final innerBranch = result.first as BranchNode;
      expect(innerBranch.first.id, 'leaf-a');
      expect(innerBranch.second.id, 'leaf-new');
    });

    test('returns unchanged tree when target not found', () {
      final root = LeafNode(id: 'root');
      final replacement = LeafNode(id: 'new');
      final result = replaceNode(root, 'nonexistent', replacement);
      expect(result.id, 'root');
    });

    test('replaces branch node itself with a replacement', () {
      final root = BranchNode(
        id: 'branch',
        direction: SplitDirection.horizontal,
        first: LeafNode(id: 'a'),
        second: LeafNode(id: 'b'),
      );
      final replacement = LeafNode(id: 'single');
      final result = replaceNode(root, 'branch', replacement);
      expect(result.id, 'single');
      expect(result, isA<LeafNode>());
    });

    test('preserves branch properties after replace', () {
      final root = BranchNode(
        id: 'branch',
        direction: SplitDirection.vertical,
        ratio: 0.3,
        first: LeafNode(id: 'a'),
        second: LeafNode(id: 'b'),
      );
      final result =
          replaceNode(root, 'a', LeafNode(id: 'new-a')) as BranchNode;
      expect(result.direction, SplitDirection.vertical);
      expect(result.ratio, 0.3);
    });
  });

  group('removeNode', () {
    test('removes root leaf returns null', () {
      final root = LeafNode(id: 'root');
      final result = removeNode(root, 'root');
      expect(result, isNull);
    });

    test('removes first child promotes second', () {
      final root = BranchNode(
        id: 'branch',
        direction: SplitDirection.horizontal,
        first: LeafNode(id: 'a'),
        second: LeafNode(id: 'b'),
      );
      final result = removeNode(root, 'a');
      expect(result, isNotNull);
      expect(result!.id, 'b');
    });

    test('removes second child promotes first', () {
      final root = BranchNode(
        id: 'branch',
        direction: SplitDirection.horizontal,
        first: LeafNode(id: 'a'),
        second: LeafNode(id: 'b'),
      );
      final result = removeNode(root, 'b');
      expect(result, isNotNull);
      expect(result!.id, 'a');
    });

    test('removes deeply nested leaf', () {
      // tree: branch1(branch2(leaf-a, leaf-b), leaf-c)
      final root = BranchNode(
        id: 'branch1',
        direction: SplitDirection.horizontal,
        first: BranchNode(
          id: 'branch2',
          direction: SplitDirection.vertical,
          first: LeafNode(id: 'leaf-a'),
          second: LeafNode(id: 'leaf-b'),
        ),
        second: LeafNode(id: 'leaf-c'),
      );

      // Remove leaf-a: branch2 should collapse, promoting leaf-b
      final result = removeNode(root, 'leaf-a') as BranchNode;
      expect(result.id, 'branch1');
      expect(result.first.id, 'leaf-b');
      expect(result.second.id, 'leaf-c');
    });

    test('returns unchanged tree when target not found', () {
      final root = BranchNode(
        id: 'branch',
        direction: SplitDirection.horizontal,
        first: LeafNode(id: 'a'),
        second: LeafNode(id: 'b'),
      );
      final result = removeNode(root, 'nonexistent');
      expect(result, isNotNull);
      expect(result!.id, 'branch');
    });

    test('removes from right subtree', () {
      // tree: branch1(leaf-a, branch2(leaf-b, leaf-c))
      final root = BranchNode(
        id: 'branch1',
        direction: SplitDirection.horizontal,
        first: LeafNode(id: 'leaf-a'),
        second: BranchNode(
          id: 'branch2',
          direction: SplitDirection.vertical,
          first: LeafNode(id: 'leaf-b'),
          second: LeafNode(id: 'leaf-c'),
        ),
      );

      // Remove leaf-c: branch2 collapses to leaf-b
      final result = removeNode(root, 'leaf-c') as BranchNode;
      expect(result.id, 'branch1');
      expect(result.first.id, 'leaf-a');
      expect(result.second.id, 'leaf-b');
    });
  });

  group('collectLeafIds', () {
    test('single leaf', () {
      final leaf = LeafNode(id: 'only');
      expect(collectLeafIds(leaf), ['only']);
    });

    test('branch with two leaves', () {
      final root = BranchNode(
        direction: SplitDirection.horizontal,
        first: LeafNode(id: 'a'),
        second: LeafNode(id: 'b'),
      );
      expect(collectLeafIds(root), ['a', 'b']);
    });

    test('nested branches', () {
      final root = BranchNode(
        direction: SplitDirection.horizontal,
        first: BranchNode(
          direction: SplitDirection.vertical,
          first: LeafNode(id: '1'),
          second: LeafNode(id: '2'),
        ),
        second: BranchNode(
          direction: SplitDirection.vertical,
          first: LeafNode(id: '3'),
          second: LeafNode(id: '4'),
        ),
      );
      expect(collectLeafIds(root), ['1', '2', '3', '4']);
    });

    test('deeply nested left-heavy tree', () {
      final root = BranchNode(
        direction: SplitDirection.horizontal,
        first: BranchNode(
          direction: SplitDirection.vertical,
          first: BranchNode(
            direction: SplitDirection.horizontal,
            first: LeafNode(id: 'deep'),
            second: LeafNode(id: 'deep2'),
          ),
          second: LeafNode(id: 'mid'),
        ),
        second: LeafNode(id: 'top'),
      );
      expect(collectLeafIds(root), ['deep', 'deep2', 'mid', 'top']);
    });
  });
}
