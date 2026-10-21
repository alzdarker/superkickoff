import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../data/db/schema.dart' as t;
import '../data/models/models.dart';

/// Builds a new career season:
///  * season row + tournament links
///  * season_teams registration for every participating club
///  * double round-robin league fixtures with weekly dates
///  * first national-cup knockout round (mid-week dates, later rounds are
///    generated lazily by [scheduleCupRound] once the previous phase ends)
class SeasonGenerator {
  SeasonGenerator(this.db, {Random? random}) : _rng = random ?? Random();

  final Database db;
  final Random _rng;

  DateTime _startDate = DateTime(2025, 8, 9);

  Future<CareerPlan> generateCareer({
    required int countryId,
    required Tournament league,
    required Tournament? cup,
    List<Tournament> internationals = const <Tournament>[],
    int startYear = 2025,
  }) async {
    _startDate = DateTime(startYear, 8, 9); // first Saturday of August-ish

    final Season season = await _insertSeason(startYear);
    await db.insert(t.seasonTournaments, <String, Object?>{
      'season_id': season.seasonId,
      'tournament_id': league.tournamentId,
      'status': t.seasonTournamentActive,
    });
    if (cup != null) {
      await db.insert(t.seasonTournaments, <String, Object?>{
        'season_id': season.seasonId,
        'tournament_id': cup.tournamentId,
        'status': t.seasonTournamentActive,
      });
    }
    for (final Tournament tour in internationals) {
      await db.insert(t.seasonTournaments, <String, Object?>{
        'season_id': season.seasonId,
        'tournament_id': tour.tournamentId,
        'status': t.seasonTournamentActive,
      });
    }

    // ------------------------------------------------ participants
    final List<Team> leagueTeams = await _teamsOf(countryId, league.divisionId);
    final List<Team> cupTeams = await _teamsOf(countryId, null);
    final Map<int, Team> allTeams = <int, Team>{};
    for (final Team tm in <Team>[...leagueTeams, ...cupTeams]) {
      allTeams[tm.teamId] = tm;
    }
    // Continental entrants: each country sends its top clubs by power.
    // Clubs already invited to a bigger competition are skipped so nobody
    // plays in two continental cups in the same season.
    final Map<int, List<int>> internationalEntrants = <int, List<int>>{};
    final Set<int> continentalInvites = <int>{};
    for (final Tournament tour in internationals) {
      final List<Team> invited = await _internationalTeams(
        tour,
        exclude: continentalInvites,
        beforeSeasonId: season.seasonId,
      );
      if (invited.length < 4) continue;
      final Map<int, Team> byId = <int, Team>{
        for (final Team tm in invited) tm.teamId: tm,
      };
      final List<int> entrants = seedByIdes(invited);
      internationalEntrants[tour.tournamentId] = entrants;
      continentalInvites.addAll(entrants);
      for (final int id in entrants) {
        allTeams[id] = byId[id]!;
      }
    }

    // ------------------------------------------------ registration
    // Coach per team comes from the team itself.
    for (final Team tm in allTeams.values) {
      await db.insert(t.seasonTeams, <String, Object?>{
        'team_id': tm.teamId,
        'season_id': season.seasonId,
        'coach_id': tm.coachId,
      });
    }

    // ------------------------------------------------ league fixtures
    final int teamCount = leagueTeams.length;
    final int rounds = teamCount >= 2 ? (teamCount - 1) * 2 : 0;
    final List<FixtureSlot> slots = doubleRoundRobin(
      leagueTeams.map((Team tm) => tm.teamId).toList(),
      _rng,
    );

    final List<Map<String, Object?>> matchRows = <Map<String, Object?>>[];
    for (final FixtureSlot slot in slots) {
      matchRows.add(
        _matchRow(
          season.seasonId,
          league.tournamentId,
          allTeams[slot.home]!,
          allTeams[slot.away]!,
          round: slot.round,
          phase: 1,
          leg: slot.leg,
          date: _iso(_leagueDate(slot.round)),
        ),
      );
    }

    // ------------------------------------------------ cup first round
    int cupPhases = 0;
    if (cup != null && cupTeams.length >= 4) {
      final List<int> surviving = seedByIdes(cupTeams);
      cupPhases = knockoutRounds(surviving.length);
      final DateTime cupDate = _cupDate(1, rounds);
      await scheduleCupRound(
        season.seasonId,
        cup.tournamentId,
        surviving,
        phase: 1,
        date: cupDate,
        allTeams: allTeams,
      );
    }

    // ------------------------------------ continental group stage / round 1
    int internationalIndex = 0;
    for (final MapEntry<int, List<int>> entry
        in internationalEntrants.entries) {
      final DateTime start = _internationalDate(internationalIndex++);
      if (entry.value.length >= 8) {
        await scheduleGroupStage(
          season.seasonId,
          entry.key,
          entry.value,
          start: start,
          allTeams: allTeams,
        );
      } else {
        await scheduleCupRound(
          season.seasonId,
          entry.key,
          entry.value,
          phase: 1,
          date: start,
          allTeams: allTeams,
        );
      }
    }

    await _insertMatches(matchRows);
    return CareerPlan(
      season: season,
      leagueTournamentId: league.tournamentId,
      cupTournamentId: cup?.tournamentId,
      leagueRounds: rounds,
      cupRounds: cupPhases,
      teamCount: allTeams.length,
      matchCount: matchRows.length,
      internationalTournamentIds: internationalEntrants.keys.toList(),
    );
  }

  /// Adds continental cups to a season that was generated before the feature
  /// existed. Existing careers keep their domestic fixtures untouched.
  Future<int> addInternationalCups({
    required Season season,
    required List<Tournament> internationals,
    required Map<int, Team> teamCache,
  }) async {
    int added = 0;
    final Set<int> continentalInvites = <int>{};
    for (final Tournament tour in internationals) {
      final List<Map<String, Object?>> linked = await db.query(
        t.seasonTournaments,
        where: 'season_id = ? AND tournament_id = ?',
        whereArgs: <Object?>[season.seasonId, tour.tournamentId],
        limit: 1,
      );
      if (linked.isNotEmpty) continue;
      final List<Team> invited = await _internationalTeams(
        tour,
        exclude: continentalInvites,
        beforeSeasonId: season.seasonId,
      );
      if (invited.length < 4) continue;
      final Map<int, Team> byId = <int, Team>{
        for (final Team tm in invited) tm.teamId: tm,
      };
      final List<int> entrants = seedByIdes(invited);
      continentalInvites.addAll(entrants);

      final List<Map<String, Object?>> registered = await db.query(
        t.seasonTeams,
        columns: <String>['team_id'],
        where: 'season_id = ?',
        whereArgs: <Object?>[season.seasonId],
      );
      final Set<int> registeredIds = <int>{
        for (final Map<String, Object?> row in registered)
          row['team_id'] as int,
      };
      for (final int id in entrants) {
        final Team team = byId[id]!;
        teamCache[id] = team;
        if (registeredIds.contains(id)) continue;
        await db.insert(t.seasonTeams, <String, Object?>{
          'team_id': id,
          'season_id': season.seasonId,
          'coach_id': team.coachId,
        });
      }
      await db.insert(t.seasonTournaments, <String, Object?>{
        'season_id': season.seasonId,
        'tournament_id': tour.tournamentId,
        'status': t.seasonTournamentActive,
      });

      final List<Map<String, Object?>> dateRows = await db.rawQuery(
        '''
        SELECT MIN(date) AS next_date FROM matches
        WHERE season_id = ? AND status = ?
      ''',
        <Object?>[season.seasonId, t.matchScheduled],
      );
      final String? nextDate = dateRows.isEmpty
          ? null
          : dateRows.first['next_date'] as String?;
      final DateTime base =
          DateTime.tryParse(nextDate ?? '') ?? DateTime(season.startYear, 8, 9);
      final DateTime date = _nextWednesday(base.add(const Duration(days: 7)));
      if (entrants.length >= 8) {
        await scheduleGroupStage(
          season.seasonId,
          tour.tournamentId,
          entrants,
          start: date,
          allTeams: teamCache,
        );
      } else {
        await scheduleCupRound(
          season.seasonId,
          tour.tournamentId,
          entrants,
          phase: 1,
          date: date,
          allTeams: teamCache,
        );
      }
      added++;
    }
    return added;
  }

  DateTime _nextWednesday(DateTime from) {
    DateTime d = from;
    while (d.weekday != DateTime.wednesday) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }

  /// Schedules 3 pre-season friendly matches for [userTeamId] before the league season kicks off.
  Future<void> schedulePreSeasonFriendlies({
    required int seasonId,
    required int userTeamId,
    required Map<int, Team> allTeams,
  }) async {
    final Team? userTeam = allTeams[userTeamId];
    if (userTeam == null) return;

    final List<Team> candidates = allTeams.values
        .where((Team t) => t.teamId != userTeamId)
        .toList();
    if (candidates.length < 3) return;
    candidates.shuffle(_rng);

    final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
    final List<DateTime> dates = <DateTime>[
      _startDate.subtract(const Duration(days: 17)),
      _startDate.subtract(const Duration(days: 10)),
      _startDate.subtract(const Duration(days: 3)),
    ];

    for (int i = 0; i < 3; i++) {
      final Team opp = candidates[i];
      final bool home = i % 2 == 0;
      rows.add(
        _matchRow(
          seasonId,
          9999,
          home ? userTeam : opp,
          home ? opp : userTeam,
          round: i + 1,
          phase: 0,
          leg: 1,
          date: _iso(dates[i]),
        ),
      );
    }
    await _insertMatches(rows);
  }

  /// Builds a group stage: clubs are spread snake-style over groups of four,
  /// then play a double round robin. The top two of every group advance to
  /// the knockout rounds, which [generateCareer] leaves for later.
  Future<int> scheduleGroupStage(
    int seasonId,
    int tournamentId,
    List<int> entrants, {
    required DateTime start,
    required Map<int, Team> allTeams,
  }) async {
    final List<int> sorted = List<int>.of(entrants)
      ..sort(
        (int a, int b) =>
            (allTeams[b]?.power ?? 0).compareTo(allTeams[a]?.power ?? 0),
      );
    final int groupCount = sorted.length ~/ 4;
    if (groupCount < 1) return 0;
    final List<List<int>> groups = List<List<int>>.generate(
      groupCount,
      (_) => <int>[],
    );
    for (int i = 0; i < sorted.length; i++) {
      final int round = i ~/ groupCount;
      final int slot = i % groupCount;
      final int index = round.isEven ? slot : groupCount - 1 - slot;
      groups[index].add(sorted[i]);
    }

    final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
    for (int g = 0; g < groups.length; g++) {
      final List<FixtureSlot> slots = doubleRoundRobin(groups[g], _rng);
      for (final FixtureSlot slot in slots) {
        final Team? home = allTeams[slot.home];
        final Team? away = allTeams[slot.away];
        if (home == null || away == null) continue;
        rows.add(
          _matchRow(
            seasonId,
            tournamentId,
            home,
            away,
            round: slot.round,
            phase: 0,
            leg: slot.leg,
            date: _iso(start.add(Duration(days: 7 * (slot.round - 1)))),
            groupId: g + 1,
          ),
        );
      }
    }
    await _insertMatches(rows);
    return groups.length;
  }

  /// Schedules the NEXT knockout round once a cup phase fully finished.
  /// [survivors] are the winning team ids (byes included). Returns the
  /// number of matches scheduled.
  Future<int> scheduleCupRound(
    int seasonId,
    int cupTournamentId,
    List<int> survivors, {
    required int phase,
    required DateTime date,
    required Map<int, Team> allTeams,
  }) async {
    final List<int> ids = List<int>.of(survivors)
      ..sort(
        (int a, int b) =>
            (allTeams[b]?.power ?? 0).compareTo(allTeams[a]?.power ?? 0),
      );
    final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
    while (ids.length > 1) {
      // Pair strongest vs weakest for balance.
      final int a = ids.removeAt(0);
      final int b = ids.removeLast();
      final Team? homeTeam = allTeams[a];
      final Team? awayTeam = allTeams[b];
      if (homeTeam == null || awayTeam == null) continue;
      rows.add(
        _matchRow(
          seasonId,
          cupTournamentId,
          homeTeam,
          awayTeam,
          round: phase,
          phase: phase,
          leg: 1,
          date: _iso(date),
        ),
      );
    }
    await _insertMatches(rows);
    return rows.length;
  }

  // ---------------------------------------------------------------- helpers

  Future<Season> _insertSeason(int startYear) async {
    final Map<String, Object?> values = <String, Object?>{
      'name': 'Season $startYear/${(startYear + 1) % 100}',
      'start_year': startYear,
      'end_year': startYear + 1,
    };
    final int id = await db.insert(t.seasons, values);
    final rows = await db.query(
      t.seasons,
      where: 'season_id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return Season.fromMap(rows.first);
  }

  /// Clubs invited to a continental competition, honouring each country's
  /// slot count. Only top-division clubs qualify and [exclude] keeps a club
  /// out of a second competition in the same season.
  Future<List<Team>> _internationalTeams(
    Tournament tour, {
    Set<int> exclude = const <int>{},
    int? beforeSeasonId,
  }) async {
    final rows = await db.query(
      t.internationalSlots,
      where: 'tournament_id = ?',
      whereArgs: <Object?>[tour.tournamentId],
    );
    final List<Team> teams = <Team>[];
    for (final Map<String, Object?> row in rows) {
      final int countryId = row['country_id'] as int;
      final int slots = (row['slots'] as int?) ?? 0;
      if (slots <= 0) continue;
      final List<Team> clubs = await _continentalQualifiers(
        countryId,
        beforeSeasonId: beforeSeasonId,
      );
      final List<Team> picked = clubs
          .where((Team tm) => !exclude.contains(tm.teamId))
          .take(slots)
          .toList();
      teams.addAll(picked);
    }
    return teams;
  }

  /// Qualification follows the latest completed domestic table when one is
  /// available; a new save falls back to club strength.
  Future<List<Team>> _continentalQualifiers(
    int countryId, {
    int? beforeSeasonId,
  }) async {
    final List<Map<String, Object?>> clubRows = await db.query(
      t.teams,
      where: 'country_id = ? AND division = 1',
      whereArgs: <Object?>[countryId],
      orderBy: 'power DESC',
    );
    final List<Team> clubs = clubRows.map(Team.fromMap).toList();
    if (beforeSeasonId == null) return _fallbackQualifiers(clubs);
    final List<Map<String, Object?>> seasonRows = await db.rawQuery(
      '''
      SELECT st.season_id, tu.tournament_id
      FROM season_tournaments st
      JOIN tournaments tu ON tu.tournament_id = st.tournament_id
      JOIN tournament_countries tc ON tc.tournament_id = tu.tournament_id
      WHERE tu.organization = ? AND tu.division_id = 1
        AND tc.country_id = ? AND st.season_id < ?
      ORDER BY st.season_id DESC
      LIMIT 1
    ''',
      <Object?>[t.orgLeague, countryId, beforeSeasonId],
    );
    if (seasonRows.isEmpty || seasonRows.first['season_id'] == null) {
      return _fallbackQualifiers(clubs);
    }
    final int seasonId = seasonRows.first['season_id'] as int;
    final int tournamentId = seasonRows.first['tournament_id'] as int;
    final List<Map<String, Object?>> results = await db.rawQuery(
      '''
      SELECT team_id, SUM(points) AS points,
             SUM(goals_for) - SUM(goals_against) AS goal_difference,
             SUM(goals_for) AS goals_for
      FROM (
        SELECT home_team_id AS team_id,
               CASE WHEN home_goals > away_goals THEN 3
                    WHEN home_goals = away_goals THEN 1 ELSE 0 END AS points,
               home_goals AS goals_for, away_goals AS goals_against
        FROM matches WHERE season_id = ? AND tournament_id = ? AND status = ?
        UNION ALL
        SELECT away_team_id AS team_id,
               CASE WHEN away_goals > home_goals THEN 3
                    WHEN away_goals = home_goals THEN 1 ELSE 0 END AS points,
               away_goals AS goals_for, home_goals AS goals_against
        FROM matches WHERE season_id = ? AND tournament_id = ? AND status = ?
      ) GROUP BY team_id
      ORDER BY points DESC, goal_difference DESC, goals_for DESC
    ''',
      <Object?>[
        seasonId,
        tournamentId,
        t.matchFinished,
        seasonId,
        tournamentId,
        t.matchFinished,
      ],
    );
    if (results.isEmpty) return _fallbackQualifiers(clubs);
    final Map<int, Team> byId = <int, Team>{
      for (final Team club in clubs) club.teamId: club,
    };
    final List<Team> ordered = <Team>[
      for (final Map<String, Object?> row in results)
        if (byId.remove(row['team_id']) case final Team club) club,
    ];
    ordered.addAll(byId.values);
    return ordered;
  }

  /// Countries outside the simulated domestic world have no table to qualify
  /// from. Rotate their leading clubs instead of selecting the same power list
  /// every season.
  List<Team> _fallbackQualifiers(List<Team> clubs) {
    final List<Team> leading = clubs.take(min(8, clubs.length)).toList()
      ..shuffle(_rng);
    return <Team>[...leading, ...clubs.skip(leading.length)];
  }

  Future<List<Team>> _teamsOf(int countryId, int? divisionId) async {
    final String where = divisionId == null
        ? 'country_id = ?'
        : 'country_id = ? AND division = ?';
    final List<Object?> args = divisionId == null
        ? <Object?>[countryId]
        : <Object?>[countryId, divisionId];
    final rows = await db.query(t.teams, where: where, whereArgs: args);
    return rows.map(Team.fromMap).toList();
  }

  Map<String, Object?> _matchRow(
    int seasonId,
    int tournamentId,
    Team home,
    Team away, {
    required int round,
    required int phase,
    required int leg,
    required String date,
    int? groupId,
  }) {
    return <String, Object?>{
      'tournament_id': tournamentId,
      'season_id': seasonId,
      'home_team_id': home.teamId,
      'away_team_id': away.teamId,
      'stadium_id': home.stadiumId,
      'round': round,
      'phase': phase,
      'group_id': groupId,
      'status': t.matchScheduled,
      'leg': leg,
      'date': date,
      'home_goals': null,
      'away_goals': null,
      'winner_id': null,
    };
  }

  Future<void> _insertMatches(List<Map<String, Object?>> rows) async {
    await db.transaction((Transaction txn) async {
      for (final Map<String, Object?> row in rows) {
        await txn.insert(t.matches, row);
      }
    });
  }

  DateTime _leagueDate(int round) =>
      _startDate.add(Duration(days: 7 * (round - 1)));

  /// Cup is on Wednesdays, interleaved: phase 1 mid-week before half-time.
  DateTime _cupDate(int phase, int leagueRounds) {
    final int spacing = max(2, leagueRounds ~/ 8);
    final int weekOffset = 2 + (phase - 1) * spacing;
    return _startDate.add(Duration(days: 7 * weekOffset - 3));
  }

  /// Continental rounds get their own mid-week slot (Tuesdays) so they never
  /// land on the domestic cup's dates (Wednesdays) or league matchdays (Saturdays).
  DateTime _internationalDate(int index) {
    final int weekOffset = 3 + index * 4;
    return _startDate.add(Duration(days: 7 * weekOffset - 4));
  }

  /// Sorts teams by power (seeding) and returns their ids.
  /// Seeds the cup by club power and trims the field to the largest power of
  /// two that fits, which keeps every knockout round evenly paired.
  List<int> seedByIdes(List<Team> teams) {
    final List<Team> sorted = List<Team>.of(teams)
      ..sort((Team a, Team b) => b.power.compareTo(a.power));
    int bracket = 1;
    while (bracket * 2 <= sorted.length) {
      bracket *= 2;
    }
    return sorted.take(bracket).map((Team tm) => tm.teamId).toList();
  }

  /// How many knockout rounds until one winner remains: n -> ceil(n/2).
  static int knockoutRounds(int teamCount) {
    int rounds = 0;
    int size = teamCount;
    while (size > 1) {
      size = (size + 1) ~/ 2;
      rounds++;
    }
    return rounds;
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Outcome of a full career generation.
class CareerPlan {
  CareerPlan({
    required this.season,
    required this.leagueTournamentId,
    required this.cupTournamentId,
    required this.leagueRounds,
    required this.cupRounds,
    required this.teamCount,
    required this.matchCount,
    this.internationalTournamentIds = const <int>[],
  });

  final Season season;
  final int leagueTournamentId;
  final int? cupTournamentId;
  final int leagueRounds;
  final int cupRounds;
  final int teamCount;
  final int matchCount;
  final List<int> internationalTournamentIds;
}

/// One direction of a round-robin match: home/away pair + round + leg.
class FixtureSlot {
  FixtureSlot(this.round, this.leg, this.home, this.away);

  final int round;
  final int leg;
  final int home;
  final int away;
}

/// Classic circle-method double round robin (n-1 rounds, mirrored legs).
/// Handles odd team counts with a bye placeholder (-1).
List<FixtureSlot> doubleRoundRobin(List<int> teamIds, [Random? random]) {
  final List<int> ids = List<int>.of(teamIds);
  if (ids.length < 2) return <FixtureSlot>[];
  ids.shuffle(random);
  if (ids.length.isOdd) ids.add(-1);

  final int half = ids.length - 1;
  final List<FixtureSlot> legs = <FixtureSlot>[];

  for (int round = 1; round <= half; round++) {
    for (int i = 0; i < ids.length ~/ 2; i++) {
      final int a = ids[i];
      final int b = ids[ids.length - 1 - i];
      if (a == -1 || b == -1) continue;
      // Alternate fixture orientation so home/away split evenly.
      final bool swap = (round + i) % 2 == 0;
      final int home = swap ? b : a;
      final int away = swap ? a : b;
      legs.add(FixtureSlot(round, 1, home, away));
    }
    // Rotate all but the first.
    final int last = ids.removeLast();
    ids.insert(1, last);
  }

  // Mirrored second half.
  final List<FixtureSlot> all = <FixtureSlot>[...legs];
  for (final FixtureSlot slot in legs) {
    all.add(FixtureSlot(slot.round + half, 2, slot.away, slot.home));
  }
  return all;
}
