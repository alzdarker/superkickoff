import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:superkickoff/data/db/app_database.dart';
import 'package:superkickoff/data/db/schema.dart' as t;
import 'package:superkickoff/data/models/models.dart';
import 'package:superkickoff/data/repositories/match_repository.dart';
import 'package:superkickoff/data/repositories/message_repository.dart';
import 'package:superkickoff/data/repositories/reference_repository.dart';
import 'package:superkickoff/data/repositories/season_repository.dart';
import 'package:superkickoff/data/repositories/squad_repository.dart';
import 'package:superkickoff/game/career_service.dart';
import 'package:superkickoff/game/match_engine.dart';
import 'package:superkickoff/game/season_generator.dart';

/// Integration test: generate a real 2025 season from the bundled database
/// into a throw-away copy so the asset stays untouched.
void main() {
  late Directory tempDir;
  late Database db;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('superkickoff_test_');
    final File source = File(p.join('assets', 'data', 'superkickoff_2025.db'));
    expect(
      source.existsSync(),
      isTrue,
      reason: 'Bundled database asset must exist',
    );
    final File target = File(p.join(tempDir.path, 'test.db'));
    await source.copy(target.path);
    db = await databaseFactory.openDatabase(
      target.path,
      options: OpenDatabaseOptions(version: 1, readOnly: false),
    );
    await AppDatabase.ensureLocalTables(db);
  });

  tearDownAll(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  Future<Map<String, Object?>> findTournament({
    required int countryId,
    required int organization,
    int? divisionId,
  }) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '''
      SELECT tu.* FROM tournaments tu
      JOIN tournament_countries tc ON tc.tournament_id = tu.tournament_id
      WHERE tc.country_id = ?
        AND tu.organization = ?
        ${divisionId == null ? '' : 'AND tu.division_id = ?'}
      LIMIT 1
    ''',
      <Object?>[countryId, organization, ?divisionId],
    );
    expect(
      rows,
      isNotEmpty,
      reason: 'No tournament organization=$organization for country $countryId',
    );
    return rows.first;
  }

  test('generates a full league + cup season', () async {
    const int countryId = 141; // Mexico, known to have an 18-team league.
    final Tournament league = Tournament.fromMap(
      await findTournament(
        countryId: countryId,
        organization: t.orgLeague,
        divisionId: 1,
      ),
    );
    final Tournament cup = Tournament.fromMap(
      await findTournament(
        countryId: countryId,
        organization: t.orgNationalCup,
      ),
    );

    final CareerPlan plan = await SeasonGenerator(
      db,
      random: null,
    ).generateCareer(countryId: countryId, league: league, cup: cup);

    expect(plan.teamCount, greaterThanOrEqualTo(18));
    expect(plan.leagueRounds, 34);
    expect(
      plan.matchCount,
      306,
      reason: '18-team double round robin: 34 rounds x 9 games',
    );

    final List<Map<String, Object?>> seasons = await db.query(t.seasons);
    expect(seasons.length, 1);
    expect(seasons.first['start_year'], 2025);

    final List<Map<String, Object?>> registered = await db.query(
      t.seasonTeams,
      where: 'season_id = ?',
      whereArgs: <Object?>[plan.season.seasonId],
    );
    expect(
      registered.length,
      greaterThanOrEqualTo(18),
      reason: 'every cup participant is registered for the season',
    );

    final List<Map<String, Object?>> matches = await db.query(
      t.matches,
      where: 'season_id = ? AND tournament_id = ?',
      whereArgs: <Object?>[plan.season.seasonId, league.tournamentId],
    );
    expect(matches.length, 306);

    // Each club plays 34 league games: 17 home + 17 away.
    final Map<int, int> appearances = <int, int>{};
    for (final Map<String, Object?> row in matches) {
      for (final String side in <String>['home_team_id', 'away_team_id']) {
        final int id = row[side] as int;
        appearances[id] = (appearances[id] ?? 0) + 1;
      }
    }
    expect(appearances.length, 18);
    expect(appearances.values.every((int v) => v == 34), isTrue);

    // All fixtures start scheduled, with parseable dates.
    for (final Map<String, Object?> row in matches) {
      expect(row['status'], t.matchScheduled);
      expect(DateTime.tryParse(row['date'] as String), isNotNull);
    }

    // Cup fixtures were generated for the same season.
    final List<Map<String, Object?>> cupMatches = await db.query(
      t.matches,
      where: 'season_id = ? AND tournament_id = ?',
      whereArgs: <Object?>[plan.season.seasonId, cup.tournamentId],
    );
    // 64 of the 74 clubs enter a six-round knockout bracket.
    expect(cupMatches.length, 32);
    expect(plan.cupRounds, 6);
  });

  test('schedules domestic and continental cup rounds', () async {
    const int countryId = 94; // Indonesia: AFC Champions League Elite + Two.
    final Tournament league = Tournament.fromMap(
      await findTournament(
        countryId: countryId,
        organization: t.orgLeague,
        divisionId: 1,
      ),
    );
    final Tournament cup = Tournament.fromMap(
      await findTournament(
        countryId: countryId,
        organization: t.orgNationalCup,
      ),
    );
    final List<Tournament> internationals = await ReferenceRepository(db)
        .internationalCups(countryId);
    expect(
      internationals.map((Tournament tour) => tour.name),
      containsAll(<String>[
        'AFC Champions League Elite',
        'AFC Champions League Two',
      ]),
    );

    final CareerPlan plan = await SeasonGenerator(db, random: Random(3))
        .generateCareer(
          countryId: countryId,
          league: league,
          cup: cup,
          internationals: internationals,
        );
    expect(plan.internationalTournamentIds.length, internationals.length);

    for (final int tournamentId in plan.internationalTournamentIds) {
      final List<Map<String, Object?>> rows = await db.query(
        t.matches,
        where: 'season_id = ? AND tournament_id = ?',
        whereArgs: <Object?>[plan.season.seasonId, tournamentId],
      );
      expect(rows, isNotEmpty, reason: 'continental cup has fixtures');
      // Every entrant is paired, so the first round has an even tie count.
      // A two-club super cup is a single match.
      expect(rows.length.isEven || rows.length == 1, isTrue);
    }

    final List<Map<String, Object?>> foreignRows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS total FROM season_teams st
      JOIN teams tm ON tm.team_id = st.team_id
      WHERE st.season_id = ? AND tm.country_id != ?
    ''',
      <Object?>[plan.season.seasonId, countryId],
    );
    expect(foreignRows.first['total'] as int, greaterThan(0));
  });

  test('adds continental cups to an existing season', () async {
    const int countryId = 185; // England: Champions League, Europa, Conference.
    final Tournament league = Tournament.fromMap(
      await findTournament(
        countryId: countryId,
        organization: t.orgLeague,
        divisionId: 1,
      ),
    );
    final Tournament cup = Tournament.fromMap(
      await findTournament(
        countryId: countryId,
        organization: t.orgNationalCup,
      ),
    );
    final SeasonGenerator generator = SeasonGenerator(db, random: Random(5));
    final CareerPlan plan = await generator.generateCareer(
      countryId: countryId,
      league: league,
      cup: cup,
    );
    expect(plan.internationalTournamentIds, isEmpty);

    final List<Tournament> internationals = await ReferenceRepository(db)
        .internationalCups(countryId);
    final List<Map<String, Object?>> registered = await db.rawQuery(
      '''
      SELECT tm.* FROM season_teams st
      JOIN teams tm ON tm.team_id = st.team_id
      WHERE st.season_id = ?
    ''',
      <Object?>[plan.season.seasonId],
    );
    final Map<int, Team> cache = <int, Team>{
      for (final Map<String, Object?> row in registered)
        row['team_id'] as int: Team.fromMap(row),
    };
    final int added = await generator.addInternationalCups(
      season: plan.season,
      internationals: internationals,
      teamCache: cache,
    );
    expect(added, internationals.length);
    for (final Tournament tour in internationals) {
      final List<Map<String, Object?>> linked = await db.query(
        t.seasonTournaments,
        where: 'season_id = ? AND tournament_id = ?',
        whereArgs: <Object?>[plan.season.seasonId, tour.tournamentId],
      );
      expect(linked, isNotEmpty);
      final List<Map<String, Object?>> fixtures = await db.query(
        t.matches,
        where: 'season_id = ? AND tournament_id = ?',
        whereArgs: <Object?>[plan.season.seasonId, tour.tournamentId],
      );
      expect(fixtures, isNotEmpty);
    }
  });

  test('continental group stage qualifies two clubs per group', () async {
    const int countryId = 94; // Indonesia: two AFC cups.
    final Tournament league = Tournament.fromMap(
      await findTournament(
        countryId: countryId,
        organization: t.orgLeague,
        divisionId: 1,
      ),
    );
    final Tournament cup = Tournament.fromMap(
      await findTournament(
        countryId: countryId,
        organization: t.orgNationalCup,
      ),
    );
    final ReferenceRepository refs = ReferenceRepository(db);
    final List<Tournament> internationals = await refs.internationalCups(
      countryId,
    );
    final SeasonGenerator generator = SeasonGenerator(db, random: Random(9));
    final CareerPlan plan = await generator.generateCareer(
      countryId: countryId,
      league: league,
      cup: cup,
      internationals: internationals,
    );
    final int seasonId = plan.season.seasonId;
    final Tournament continental = internationals.first;

    final List<Map<String, Object?>> groupMatchRows = await db.query(
      t.matches,
      where: 'season_id = ? AND tournament_id = ?',
      whereArgs: <Object?>[seasonId, continental.tournamentId],
    );
    expect(groupMatchRows, isNotEmpty);
    expect(
      groupMatchRows.every(
        (Map<String, Object?> row) => row['group_id'] != null,
      ),
      isTrue,
      reason: 'continental fixtures start with a group stage',
    );
    final SeasonRepository seasons = SeasonRepository(db);
    final List<GroupTable> groups = await seasons.groupTables(
      seasonId,
      continental.tournamentId,
    );
    expect(groups.length, greaterThanOrEqualTo(2));
    for (final GroupTable group in groups) {
      expect(group.rows.length, 4);
      expect(
        groupMatchRows
            .where(
              (Map<String, Object?> row) => row['group_id'] == group.groupId,
            )
            .length,
        12,
        reason: 'four clubs play a double round robin',
      );
    }

    // Finish every group match, then let the service build the knockout round.
    for (final Map<String, Object?> row in groupMatchRows) {
      await db.update(
        t.matches,
        <String, Object?>{
          'status': t.matchFinished,
          'home_goals': 1,
          'away_goals': 0,
          'winner_id': row['home_team_id'],
        },
        where: 'match_id = ?',
        whereArgs: <Object?>[row['match_id']],
      );
    }
    final List<Map<String, Object?>> registered = await db.rawQuery(
      '''
      SELECT tm.* FROM season_teams st
      JOIN teams tm ON tm.team_id = st.team_id
      WHERE st.season_id = ?
    ''',
      <Object?>[seasonId],
    );
    final Map<int, Team> cache = <int, Team>{
      for (final Map<String, Object?> row in registered)
        row['team_id'] as int: Team.fromMap(row),
    };
    final CareerService service = CareerService(
      db,
      refs: refs,
      seasons: seasons,
      squads: SquadRepository(db),
      matches: MatchRepository(db),
      messages: MessageRepository(db),
      engine: MatchEngine(random: Random(9)),
      generator: generator,
      random: Random(9),
    );
    final bool scheduled = await service.maybeScheduleNextCupRound(
      seasonId: seasonId,
      cupTournamentId: continental.tournamentId,
      teamCache: cache,
    );
    expect(scheduled, isTrue);

    final List<Map<String, Object?>> knockout = await db.query(
      t.matches,
      where:
          'season_id = ? AND tournament_id = ? AND group_id IS NULL '
          'AND phase = 1',
      whereArgs: <Object?>[seasonId, continental.tournamentId],
    );
    expect(
      knockout.length,
      groups.length,
      reason: 'two qualifiers per group make one tie per group',
    );

    // Each knockout tie must pair clubs from different groups.
    final Map<int, int> teamToGroup = <int, int>{};
    for (final GroupTable g in groups) {
      for (final StandingRow r in g.rows) {
        teamToGroup[r.teamId] = g.groupId;
      }
    }
    for (final Map<String, Object?> tie in knockout) {
      final int homeGroup = teamToGroup[tie['home_team_id']]!;
      final int awayGroup = teamToGroup[tie['away_team_id']]!;
      expect(
        homeGroup,
        isNot(equals(awayGroup)),
        reason: 'clubs from the same group must not face each other in the first knockout round',
      );
    }
  });

  test('double round robin pairs every team once per round', () {
    final List<int> ids = <int>[1, 2, 3, 4, 5, 6, 7, 8, 9];
    final List<FixtureSlot> slots = doubleRoundRobin(ids);
    expect(slots.length, 9 * 8); // every ordered pair once
    final Set<String> pairs = <String>{
      for (final FixtureSlot s in slots) '${s.home}-${s.away}',
    };
    expect(pairs.length, slots.length);
    for (final FixtureSlot slot in slots) {
      expect(slot.home == slot.away, isFalse);
    }
  });
}
