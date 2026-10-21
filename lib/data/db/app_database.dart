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
  static String? _path;
  static String? _sessionPath;

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
    _path = target;
    _sessionPath = '$target.session';
    _db = await databaseFactory.openDatabase(
      target,
      options: OpenDatabaseOptions(version: 1, readOnly: false),
    );
    await ensureLocalTables(_db!);
    return _db!;
  }

  /// Tables that belong to the save game rather than the bundled reference
  /// data. Created lazily so existing installs pick them up on the next run.
  static Future<void> ensureLocalTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${t.managerProfile} (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        name TEXT NOT NULL,
        country_id INTEGER NOT NULL
      )
    ''');
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
      CREATE TABLE IF NOT EXISTS ${t.teamYouthAcademy} (
        team_id INTEGER PRIMARY KEY,
        level INTEGER NOT NULL DEFAULT 1,
        last_graduated_season INTEGER,
        last_graduated_date TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${t.competitionPrizeRules} (
        tournament_id INTEGER PRIMARY KEY,
        base_pool INTEGER NOT NULL,
        participation_per_club INTEGER NOT NULL DEFAULT 0,
        win_bonus INTEGER NOT NULL DEFAULT 0,
        draw_bonus INTEGER NOT NULL DEFAULT 0,
        champion_bonus INTEGER NOT NULL DEFAULT 0,
        runner_up_bonus INTEGER NOT NULL DEFAULT 0,
        position_weights TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${t.competitionPrizeAwards} (
        award_id INTEGER PRIMARY KEY AUTOINCREMENT,
        season_id INTEGER NOT NULL,
        tournament_id INTEGER NOT NULL,
        team_id INTEGER NOT NULL,
        amount INTEGER NOT NULL,
        reason TEXT,
        created_date TEXT NOT NULL,
        UNIQUE (season_id, tournament_id, team_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${t.transferOffers} (
        offer_id INTEGER PRIMARY KEY AUTOINCREMENT,
        player_id INTEGER NOT NULL,
        from_team_id INTEGER NOT NULL,
        to_team_id INTEGER NOT NULL,
        offer_amount INTEGER NOT NULL,
        player_value INTEGER NOT NULL,
        status INTEGER NOT NULL DEFAULT 1,
        counter_amount INTEGER,
        proposed_salary INTEGER,
        proposed_duration_years INTEGER,
        created_date TEXT NOT NULL,
        updated_date TEXT,
        message_id INTEGER,
        is_loan INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${t.academyProspects} (
        prospect_id INTEGER PRIMARY KEY AUTOINCREMENT,
        team_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        age INTEGER NOT NULL DEFAULT 17,
        position_id INTEGER NOT NULL,
        power INTEGER NOT NULL,
        potential INTEGER NOT NULL,
        stars INTEGER NOT NULL DEFAULT 0,
        profile TEXT NOT NULL DEFAULT 'D',
        height INTEGER NOT NULL DEFAULT 178,
        country_id INTEGER NOT NULL,
        created_date TEXT NOT NULL,
        signed INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${t.scouts} (
        scout_id INTEGER PRIMARY KEY AUTOINCREMENT,
        team_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        stars INTEGER NOT NULL,
        region TEXT,
        salary INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'idle',
        return_date TEXT,
        last_report TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${t.scoutReports} (
        report_id INTEGER PRIMARY KEY AUTOINCREMENT,
        team_id INTEGER NOT NULL,
        scout_id INTEGER NOT NULL,
        scout_name TEXT NOT NULL,
        region TEXT NOT NULL,
        date TEXT NOT NULL,
        player_name TEXT NOT NULL,
        age INTEGER NOT NULL,
        position_id INTEGER NOT NULL,
        power INTEGER NOT NULL,
        potential INTEGER NOT NULL,
        value INTEGER NOT NULL,
        country_id INTEGER NOT NULL,
        signed INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      INSERT OR IGNORE INTO ${t.tournaments} (
        tournament_id, name, division_id, status, organization, rounds,
        play_days, slots, points, promotion_slots, relegation_spots,
        prize_teams, prize_top_scorer, prize_mvp
      ) VALUES (
        9999, 'Pre-Season Friendly', 0, 1, 4, 3,
        '3,6', '2', 0, 0, 0, 0, 0, 0
      )
    ''');
    final List<Map<String, Object?>> offerColumns = await db.rawQuery(
      'PRAGMA table_info(${t.transferOffers})',
    );
    if (!offerColumns.any(
      (Map<String, Object?> column) => column['name'] == 'is_loan',
    )) {
      await db.execute(
        'ALTER TABLE ${t.transferOffers} ADD COLUMN is_loan INTEGER NOT NULL DEFAULT 0',
      );
    }
    final List<Map<String, Object?>> academyColumns = await db.rawQuery(
      'PRAGMA table_info(${t.teamYouthAcademy})',
    );
    if (!academyColumns.any(
      (Map<String, Object?> column) => column['name'] == 'last_graduated_date',
    )) {
      await db.execute(
        'ALTER TABLE ${t.teamYouthAcademy} ADD COLUMN last_graduated_date TEXT',
      );
    }
    final List<Map<String, Object?>> messageColumns = await db.rawQuery(
      'PRAGMA table_info(${t.messages})',
    );
    if (!messageColumns.any(
      (Map<String, Object?> column) => column['name'] == 'transfer_offer_id',
    )) {
      await db.execute(
        'ALTER TABLE ${t.messages} ADD COLUMN transfer_offer_id INTEGER',
      );
    }
    // The bundled database only gave Persib a transfer budget. Backfill every
    // zero-budget club once, scaling available funds to club strength.
    await db.execute('''
      UPDATE teams
      SET budget = CASE
        WHEN power <= 40 THEN 500000
        ELSE MAX(500000, (power - 40) * (power - 40) * 40000)
      END
      WHERE COALESCE(budget, 0) <= 0
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
    await ensureLocalTables(_db!);
    return _db!;
  }

  /// Captures the pre-session save so "Don't save" can restore it.
  static Future<void> beginSession() async {
    final String? path = _path;
    if (path == null || _db == null) return;
    final File snapshot = File(_sessionPath!);
    if (!snapshot.existsSync()) await File(path).copy(snapshot.path);
  }

  /// Commits or restores the snapshot created by [beginSession].
  static Future<void> finishSession({required bool save}) async {
    final String? path = _path;
    final String? snapshotPath = _sessionPath;
    if (path == null || snapshotPath == null) return;
    final File snapshot = File(snapshotPath);
    if (save || !snapshot.existsSync()) {
      if (snapshot.existsSync()) await snapshot.delete();
      return;
    }
    await _db?.close();
    _db = null;
    await snapshot.copy(path);
    await snapshot.delete();
    await open();
  }

  /// Starts a genuinely fresh local career without mutating the bundled DB.
  static Future<void> reset() async {
    final Directory docs = await getApplicationDocumentsDirectory();
    final String target = p.join(docs.path, dbName);
    await _db?.close();
    _db = null;
    final File snapshot = File('$target.session');
    if (snapshot.existsSync()) await snapshot.delete();
    final ByteData asset = await rootBundle.load('assets/data/$dbName');
    await File(target).writeAsBytes(asset.buffer.asUint8List(), flush: true);
    _path = target;
    _sessionPath = '$target.session';
    await open();
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
