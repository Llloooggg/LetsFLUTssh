import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/db/database.dart';

import '../../generated_drift_schema/schema.dart';

/// Verifies that [AppDatabase.migration] produces the schema captured
/// in `drift_schemas/drift_schema_v1.json` when started from an empty
/// database, and that [AppDatabase.schemaVersion] matches the latest
/// snapshot on file.
///
/// v1 is the permanent floor; any future `from{N-1}to{N}` migration
/// registers a new snapshot here and adds its own
/// `verifier.migrateAndValidate(db, N)` test. Keeping the snapshots
/// under version control is what lets those future tests prove the
/// migration actually produces the new shape — without them,
/// `addColumn(x, y)` with the wrong column name would ship.
///
/// Regenerate after a schema bump (see Makefile):
///   make drift-schema-dump
///   make drift-schema-generate
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('schemaVersion matches latest snapshot on file', () {
    final db = AppDatabase(NativeDatabase.memory());
    expect(db.schemaVersion, GeneratedHelper.versions.last);
    db.close();
  });

  test('migration strategy produces the current schema from empty', () async {
    final connection = await verifier.startAt(1);
    final db = AppDatabase(connection);
    // Runs drift's schema-diff against the captured snapshot for v1.
    await verifier.migrateAndValidate(db, 1);
    await db.close();
  });
}
