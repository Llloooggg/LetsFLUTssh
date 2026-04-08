import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/features/file_browser/breadcrumb_path.dart';

void main() {
  group('isWindowsPath', () {
    test('detects drive letter paths', () {
      expect(isWindowsPath('C:\\Users\\test'), isTrue);
      expect(isWindowsPath('D:\\'), isTrue);
      expect(isWindowsPath('z:\\data'), isTrue);
    });

    test('rejects non-Windows paths', () {
      expect(isWindowsPath('/home/user'), isFalse);
      expect(isWindowsPath('/'), isFalse);
      expect(isWindowsPath(''), isFalse);
      expect(isWindowsPath('a'), isFalse);
    });
  });

  group('parseBreadcrumbPath', () {
    test('parses Unix root path', () {
      final bc = parseBreadcrumbPath('/');
      expect(bc.isWindows, isFalse);
      expect(bc.rootPath, '/');
      expect(bc.rootLabel, isNull);
      expect(bc.navParts, isEmpty);
    });

    test('parses Unix absolute path', () {
      final bc = parseBreadcrumbPath('/home/user/docs');
      expect(bc.isWindows, isFalse);
      expect(bc.rootPath, '/');
      expect(bc.rootLabel, isNull);
      expect(bc.navParts, ['home', 'user', 'docs']);
    });

    test('parses Windows drive path', () {
      final bc = parseBreadcrumbPath('C:\\Users\\test');
      expect(bc.isWindows, isTrue);
      expect(bc.rootPath, 'C:\\');
      expect(bc.rootLabel, 'C:');
      expect(bc.navParts, ['Users', 'test']);
      expect(bc.allParts, ['C:', 'Users', 'test']);
    });

    test('parses Windows root only', () {
      final bc = parseBreadcrumbPath('D:\\');
      expect(bc.isWindows, isTrue);
      expect(bc.rootPath, 'D:\\');
      expect(bc.rootLabel, 'D:');
      expect(bc.navParts, isEmpty);
    });
  });

  group('buildPathForSegment', () {
    test('builds Unix path for segment index', () {
      final bc = parseBreadcrumbPath('/home/user/docs');
      expect(buildPathForSegment(bc, 0), '/home');
      expect(buildPathForSegment(bc, 1), '/home/user');
      expect(buildPathForSegment(bc, 2), '/home/user/docs');
    });

    test('builds Windows path for segment index', () {
      final bc = parseBreadcrumbPath('C:\\Users\\test\\data');
      expect(buildPathForSegment(bc, 0), 'C:\\Users');
      expect(buildPathForSegment(bc, 1), 'C:\\Users\\test');
      expect(buildPathForSegment(bc, 2), 'C:\\Users\\test\\data');
    });
  });
}
