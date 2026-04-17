import 'package:path/path.dart' as p;

/// Generates a destination path that does not collide with existing
/// siblings, by appending " (N)" before the file extension.
///
/// [path] is the original desired destination.
/// [exists] probes whether a candidate path is already taken (remote
/// stat or local File.exists).
/// [isPosix] controls which path style is used — POSIX for remote
/// SFTP, native for local filesystem.
///
/// Examples:
/// * `report.txt` → `report (1).txt`
/// * `archive.tar.gz` → `archive.tar (1).gz` (only the final extension
///   is preserved; this matches the behavior of common file managers
///   such as GNOME Files and Finder).
/// * `README` → `README (1)`
///
/// Increments the suffix until an unused name is found, giving up
/// after [maxAttempts] to avoid an unbounded loop.
Future<String> uniqueSiblingName(
  String path,
  Future<bool> Function(String candidate) exists, {
  bool isPosix = false,
  int maxAttempts = 10000,
}) async {
  final ctx = isPosix ? p.posix : p.context;
  final dir = ctx.dirname(path);
  final base = ctx.basename(path);
  final ext = ctx.extension(base);
  final stem = ext.isEmpty ? base : base.substring(0, base.length - ext.length);

  for (var i = 1; i <= maxAttempts; i++) {
    final candidate = ctx.join(dir, '$stem ($i)$ext');
    if (!await exists(candidate)) return candidate;
  }
  throw StateError(
    'Could not find a unique name for $path after $maxAttempts attempts',
  );
}
