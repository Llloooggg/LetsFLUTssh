import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/sftp/errors.dart';

void main() {
  group('SFTPError', () {
    test('stores message, cause, and path', () {
      final error = SFTPError(
        'test error',
        cause: Exception('root'),
        path: '/remote/file.txt',
      );
      expect(error.message, 'test error');
      expect(error.cause, isA<Exception>());
      expect(error.path, '/remote/file.txt');
    });

    test('statusCode returns null when cause is not SftpStatusError', () {
      const error = SFTPError('fail', cause: 'not sftp');
      expect(error.statusCode, isNull);
    });

    test('statusCode returns null when no cause', () {
      const error = SFTPError('fail');
      expect(error.statusCode, isNull);
    });

    test('userMessage returns message when no cause', () {
      const error = SFTPError('simple error');
      expect(error.userMessage, 'simple error');
    });

    test('userMessage appends root cause', () {
      final error = SFTPError('op failed', cause: Exception('timeout'));
      expect(error.userMessage, contains('op failed'));
      expect(error.userMessage, contains('timeout'));
    });

    test('userMessage does not duplicate when cause matches message', () {
      const error = SFTPError('same', cause: 'same');
      expect(error.userMessage, 'same');
    });

    test('wrap creates error with operation name', () {
      final error = SFTPError.wrap(Exception('io'), 'list', '/home');
      expect(error.message, 'SFTP list failed');
      expect(error.path, '/home');
      expect(error.cause, isA<Exception>());
    });

    test('wrap without path sets path to null', () {
      final error = SFTPError.wrap(Exception('io'), 'stat');
      expect(error.path, isNull);
    });

    test('toString includes all fields', () {
      final error = SFTPError(
        'read failed',
        cause: Exception('eof'),
        path: '/tmp/file',
      );
      final s = error.toString();
      expect(s, contains('SFTPError'));
      expect(s, contains('read failed'));
      expect(s, contains('/tmp/file'));
      expect(s, contains('eof'));
    });

    test('toString minimal without optional fields', () {
      const error = SFTPError('basic');
      expect(error.toString(), 'SFTPError: basic');
    });

    test('nested SFTPError cause shows recursive userMessage', () {
      const inner = SFTPError('inner fail');
      const outer = SFTPError('outer fail', cause: inner);
      expect(outer.userMessage, 'outer fail (inner fail)');
    });
  });

  group('SFTPError — _rootCauseMessage prefix stripping', () {
    // The Rust transport surfaces russh-sftp errors as strings carrying
    // a type prefix; the userMessage strips a known prefix so the UI
    // shows the bare detail. Each branch is exercised with a
    // string-typed cause that begins with that prefix.

    test('strips SftpStatusError: prefix', () {
      const error = SFTPError(
        'op failed',
        cause: 'SftpStatusError: no such file',
      );
      expect(error.userMessage, 'op failed (no such file)');
    });

    test('strips SftpError: prefix', () {
      const error = SFTPError('op failed', cause: 'SftpError: protocol error');
      expect(error.userMessage, 'op failed (protocol error)');
    });

    test('strips SftpAbortError: prefix', () {
      const error = SFTPError('op failed', cause: 'SftpAbortError: cancelled');
      expect(error.userMessage, 'op failed (cancelled)');
    });

    test('non-prefixed string cause passes through verbatim', () {
      const error = SFTPError('op failed', cause: 'plain detail');
      expect(error.userMessage, 'op failed (plain detail)');
    });

    test('userMessage drops an empty-string cause', () {
      // The `causeStr.isNotEmpty` guard keeps an empty cause from
      // producing a bare "message ()".
      const error = SFTPError('op failed', cause: '');
      expect(error.userMessage, 'op failed');
    });
  });
}
