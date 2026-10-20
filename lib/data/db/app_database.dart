import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'schema.dart' as t;

/// Single access point for the SQLite game database.
///
/// The bundled asset [dbName] is copied into the app documents directory on
/// first launch (asset databases are read-only), then opened as a normal
/// writable SQLite database. It serves both as reference data (teams, players,
/// tournaments...) and as the save-game store (seasons, fixtures, results).
class AppDatabase {
  AppDatabase._();

  static const String dbName = 'superkickoff_2025.db';
  static Database? _db;

  /// Opens (and lazily installs) the database. Desktop platforms use
  /// [sqflite_common_ffi]; Android/iOS use the default sqflite bindings.
  static Future<Database> open() async {
    if (_db != null) return _db!;
    if (!Platform.isAndroid && !Platform.isIOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final Directory docs = await getApplicationDocumentsDirectory();
    final String target = p.join(docs.path, dbName);
    final File file = File(target);
    if (!file.existsSync()) {
      final ByteData asset = await rootBundle.load('assets/data/$dbName');
      final List<int> bytes = asset.buffer.asUint8List();
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    }
    _db = await databaseFactory.openDatabase(
      target,
      options: OpenDatabaseOptions(version: 1, readOnly: false),
    );
    await _ensureLocalTables(_db!);
    return _db!;
  }

  /// Tables that belong to the save game rather than the bundled reference
  /// data. Created lazily so existing installs pick them up on the next run.
  static Future<void> _ensureLocalTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${t.teamTactics} (
        team_id INTEGER PRIMARY KEY,
        formation TEXT NOT NULL DEFAULT '4-4-2'
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${t.teamLineups} (
        team_id INTEGER NOT NULL,
        slot INTEGER NOT NULL,
        player_id INTEGER NOT NULL,
        PRIMARY KEY (team_id, slot)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${t.teamTraining} (
        team_id INTEGER PRIMARY KEY,
        season_id INTEGER NOT NULL,
        last_match_count INTEGER NOT NULL DEFAULT -1,
        sessions INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      UPDATE teams
      SET abbreviation = CASE name
        WHEN 'Persija' THEN 'PSJ'
        WHEN 'Persebaya' THEN 'PSB'
        WHEN 'Persijap' THEN 'PSJ'
        WHEN 'Persib' THEN 'PSB'
        WHEN 'Persik' THEN 'PSK'
        WHEN 'Persis' THEN 'PSS'
        WHEN 'Persita' THEN 'PST'
        WHEN 'Persekat' THEN 'PKT'
        WHEN 'Persiraja' THEN 'PSR'
        WHEN 'Persela' THEN 'PSL'
        WHEN 'Persiba' THEN 'PSB'
        WHEN 'Persiku' THEN 'PKU'
        WHEN 'Persipal' THEN 'PSP'
        WHEN 'Persipura' THEN 'PSP'
        WHEN 'Persipa' THEN 'PSP'
        WHEN 'Persibo' THEN 'PSB'
        WHEN 'Persikabo 1973' THEN 'PKB'
        WHEN 'Persikota' THEN 'PKT'
        WHEN 'Persewar' THEN 'PSW'
        WHEN 'Perserang' THEN 'PSR'
        WHEN 'Persekabpas' THEN 'PKP'
        WHEN 'Persikutim United' THEN 'PKU'
        WHEN 'Persikad' THEN 'PKD'
      END
      WHERE country_id = (SELECT country_id FROM countries WHERE name = 'Indonesia')
        AND abbreviation = 'Per'
    ''');
  }

  /// Test/dev helper: open an arbitrary file directly.
  static Future<Database> openFile(String path) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    _db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 1, readOnly: false),
    );
    await _ensureLocalTables(_db!);
    return _db!;
  }

  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// Progress reported while the long career-generation runs.
  static final ValueNotifier<String> status = ValueNotifier<String>(
    'Preparing database...',
  );
}
