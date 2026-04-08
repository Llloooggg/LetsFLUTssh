/// Parsed breadcrumb path segments for file browser navigation.
typedef BreadcrumbPath = ({
  bool isWindows,
  List<String> allParts,
  String rootPath,
  String? rootLabel,
  List<String> navParts,
});

/// Parses a file path into breadcrumb segments.
BreadcrumbPath parseBreadcrumbPath(String currentPath) {
  final isWindows = isWindowsPath(currentPath);
  final separator = isWindows ? RegExp(r'[/\\]') : RegExp(r'/');
  final parts = currentPath.split(separator)..removeWhere((p) => p.isEmpty);
  final rootPath = isWindows && parts.isNotEmpty ? '${parts[0]}\\' : '/';
  final rootLabel = isWindows && parts.isNotEmpty ? parts[0] : null;
  final navParts = isWindows ? parts.skip(1).toList() : parts;
  return (
    isWindows: isWindows,
    allParts: parts,
    rootPath: rootPath,
    rootLabel: rootLabel,
    navParts: navParts,
  );
}

/// Builds the full path for navigating to breadcrumb segment at [index].
String buildPathForSegment(BreadcrumbPath path, int index) {
  if (path.isWindows) {
    return [
      path.allParts[0],
      ...path.navParts.sublist(0, index + 1),
    ].join('\\');
  }
  return '/${path.navParts.sublist(0, index + 1).join('/')}';
}

/// Returns true if [path] looks like a Windows drive path (e.g. `C:\...`).
bool isWindowsPath(String path) =>
    path.length >= 2 &&
    path[1] == ':' &&
    RegExp(r'^[A-Za-z]$').hasMatch(path[0]);
