import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../core/format.dart' as fmt;
import '../data/db/app_database.dart';
import '../data/db/schema.dart' as t;
import '../data/models/models.dart';
import '../data/repositories/match_repository.dart';
import '../data/repositories/message_repository.dart';
import '../data/repositories/reference_repository.dart';
import '../data/repositories/season_repository.dart';
import '../data/repositories/squad_repository.dart';
import '../game/career_service.dart';
import '../game/formation.dart';
import '../game/match_engine.dart';
import '../game/season_generator.dart';
import '../game/training.dart';

/// Presentation-facing career state. One instance lives above the app and
/// notifies widgets whenever the career world changes.
class CareerProvider extends ChangeNotifier {
  CareerProvider();

  late final Database _db;
  late final ReferenceRepository _refs;
  late final SeasonRepository _seasons;
  late final SquadRepository _squads;
  late final MatchRepository _matchRepo;
  late final MessageRepository _messages;
  late final CareerService _service;
  late final MatchEngine _engine;
  final Random _rng = Random();

  bool initialized = false;
  bool hasCareer = false;
  bool busy = false;
  String busyStatus = '';

  Season? season;
  Tournament? league;
  Tournament? cup;

  /// Every knockout competition of the season: domestic cup plus continental
  /// cups such as the Champions League or AFC Champions League.
  List<Tournament> cups = <Tournament>[];
  int userTeamId = 0;
  Team? userTeam;
  Map<int, Team> teamCache = <int, Team>{};

  List<FixtureMatch> upcoming = <FixtureMatch>[];
  String? nextDate;
  List<FixtureMatch> matchesToday = <FixtureMatch>[];

  /// The matchday that just finished, kept after the world advances so the
  /// results screen can show every game played on that date.
  List<FixtureMatch> lastMatchday = <FixtureMatch>[];
  Map<int, Team> lastMatchdayTeams = <int, Team>{};
  List<StandingRow> standings = <StandingRow>[];

  /// Group tables of continental cups, keyed by tournament id.
  Map<int, List<GroupTable>> cupGroups = <int, List<GroupTable>>{};
  List<LeaderRow> topScorers = <LeaderRow>[];
  List<LeaderRow> topAssists = <LeaderRow>[];
  List<LeaderRow> topCleanSheets = <LeaderRow>[];
  List<LeaderRow> topRated = <LeaderRow>[];

  /// User club leaderboards and the tactic chosen for the next match.
  List<LeaderRow> clubTopScorers = <LeaderRow>[];
  List<LeaderRow> clubTopAssists = <LeaderRow>[];
  List<LeaderRow> clubTopRated = <LeaderRow>[];
  Formation formation = Formation.f442;

  /// Saved XI for the formation pitch: slot index -> player id.
  Map<int, int> lineup = <int, int>{};
  List<Message> inbox = <Message>[];
  int unreadCount = 0;
  int week = 0;

  // Live match session (filled while watching a match).
  LiveMatchSession? liveSession;

  // ------------------------------------------------------------ bootstrap

  Future<void> init() async {
    _db = await AppDatabase.open();
    _refs = ReferenceRepository(_db);
    _seasons = SeasonRepository(_db);
    _squads = SquadRepository(_db);
    _matchRepo = MatchRepository(_db);
    _messages = MessageRepository(_db);
    _engine = MatchEngine();
    _service = CareerService(
      _db,
      refs: _refs,
      seasons: _seasons,
      squads: _squads,
      matches: _matchRepo,
      messages: _messages,
      engine: _engine,
      generator: SeasonGenerator(_db, random: _rng),
      random: _rng,
    );
    initialized = true;
    await _loadCareerState();
  }

  Future<void> _loadCareerState() async {
    hasCareer = await _seasons.hasCareer();
    if (!hasCareer) {
      notifyListeners();
      return;
    }
    season = await _seasons.currentSeason();
    await _deriveCareerContext();
    await refreshWorld();
  }

  /// Recomputes userTeam/league/cup/inbox from the persisted DB state.
  Future<void> _deriveCareerContext() async {
    final int? storedTeamId = await _latestCareerTeam();
    if (storedTeamId == null) {
      hasCareer = false;
      return;
    }
    userTeamId = storedTeamId;
    userTeam = await _refs.teamById(userTeamId);
    if (userTeam == null) {
      hasCareer = false;
      return;
    }
    league = await _leagueFor(userTeam!);
    await _loadCups(season!.seasonId);
    // Cache every team that participates this season.
    final rows = await _db.rawQuery(
      '''
      SELECT tm.* FROM season_teams st
      JOIN teams tm ON tm.team_id = st.team_id
      WHERE st.season_id = ?
    ''',
      <Object?>[season!.seasonId],
    );
    teamCache = <int, Team>{
      for (final Map<String, Object?> row in rows)
        row['team_id'] as int: Team.fromMap(row),
    };
    await _ensureInternationalCups();
  }

  /// Older saves were created without continental competitions. Add them once
  /// when such a save is loaded so existing careers get the new tournaments.
  Future<void> _ensureInternationalCups() async {
    final Season? current = season;
    final Team? team = userTeam;
    if (current == null || team == null) return;
    if (cups.any((Tournament tour) => tour.isInternational)) return;
    final List<Tournament> internationals = await _refs.internationalCups(
      team.countryId,
    );
    if (internationals.isEmpty) return;
    final int added = await SeasonGenerator(_db, random: _rng)
        .addInternationalCups(
          season: current,
          internationals: internationals,
          teamCache: teamCache,
        );
    if (added > 0) await _loadCups(current.seasonId);
  }

  Future<void> _loadCups(int seasonId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT tu.* FROM season_tournaments st
      JOIN tournaments tu ON tu.tournament_id = st.tournament_id
      WHERE st.season_id = ? AND tu.organization IN (?, ?)
      ORDER BY tu.tournament_id ASC
    ''',
      <Object?>[seasonId, t.orgNationalCup, t.orgInternational],
    );
    cups = rows.map(Tournament.fromMap).toList();
    cup = null;
    for (final Tournament tour in cups) {
      if (tour.isNationalCup) {
        cup = tour;
        break;
      }
    }
  }

  /// The career row stores the managed club per season (career_history).
  Future<int?> _latestCareerTeam() async {
    final rows = await _db.query(
      t.careerHistory,
      orderBy: 'season_id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['team_id'] as int?;
  }

  Future<Tournament?> _leagueFor(Team team) async {
    final rows = await _db.rawQuery(
      '''
      SELECT tu.* FROM tournaments tu
      JOIN tournament_countries tc ON tc.tournament_id = tu.tournament_id
      WHERE tu.organization = ? AND tc.country_id = ? AND tu.division_id = ?
      LIMIT 1
    ''',
      <Object?>[t.orgLeague, team.countryId, team.division],
    );
    return rows.isEmpty ? null : Tournament.fromMap(rows.first);
  }

  // -------------------------------------------------------------- setup flow

  Future<List<Map<String, Object?>>> playableCountries() =>
      _refs.playableCountries();

  Future<Tournament?> tournamentById(int id) => _refs.tournamentById(id);

  Future<List<Map<String, Object?>>> leaguesForCountry(int countryId) =>
      _refs.leaguesForCountry(countryId);

  Future<List<Map<String, Object?>>> teamsForLeague(
    int countryId,
    int divisionId,
  ) async {
    final Map<String, Object?>? cupRow = await _refs.nationalCup(countryId);
    cup = cupRow == null ? null : Tournament.fromMap(cupRow);
    return _refs
        .teamsForDivision(countryId, divisionId)
        .then(
          (List<Team> list) => list
              .map(
                (Team tm) => <String, Object?>{
                  'team_id': tm.teamId,
                  'name': tm.name,
                  'power': tm.power,
                  'value': tm.value,
                  'budget': tm.budget,
                  'division': tm.division,
                },
              )
              .toList(),
        );
  }

  /// Generates the whole season for a brand new career.
  Future<void> startCareer({
    required int countryId,
    required Tournament leagueTournament,
    required int teamId,
    required void Function(String) onProgress,
  }) async {
    busy = true;
    onProgress('Registering teams...');
    final Map<String, Object?>? cupRow = await _refs.nationalCup(countryId);
    final Tournament? cupTournament = cupRow == null
        ? null
        : Tournament.fromMap(cupRow);
    final String label = 'Generating fixtures...';
    onProgress(label);
    await _serviceCareerGeneration(
      countryId,
      leagueTournament,
      cupTournament,
      teamId,
      onProgress,
    );
    busy = false;
    notifyListeners();
  }

  Future<void> _serviceCareerGeneration(
    int countryId,
    Tournament leagueTournament,
    Tournament? cupTournament,
    int teamId,
    void Function(String) onProgress,
  ) async {
    final CareerPlan plan = await SeasonGenerator(_db, random: _rng)
        .generateCareer(
          countryId: countryId,
          league: leagueTournament,
          cup: cupTournament,
          internationals: await _refs.internationalCups(countryId),
        );
    onProgress('Saving career...');
    // Persist the manager pick for continuation across restarts.
    await _db.insert(t.careerHistory, <String, Object?>{
      'team_id': teamId,
      'season_id': plan.season.seasonId,
      'country_id': countryId,
    });
    season = plan.season;
    userTeamId = teamId;
    userTeam = await _refs.teamById(teamId);
    league = leagueTournament;
    cup = cupTournament;
    await _loadCups(plan.season.seasonId);
    final rows = await _db.rawQuery(
      '''
      SELECT tm.* FROM season_teams st
      JOIN teams tm ON tm.team_id = st.team_id
      WHERE st.season_id = ?
    ''',
      <Object?>[plan.season.seasonId],
    );
    teamCache = <int, Team>{
      for (final Map<String, Object?> row in rows)
        row['team_id'] as int: Team.fromMap(row),
    };
    hasCareer = true;
    await refreshWorld();
  }

  // ------------------------------------------------------------- world state

  Future<void> refreshWorld() async {
    if (season == null || userTeamId == 0) {
      notifyListeners();
      return;
    }
    upcoming = await _service.upcomingMatches(season!.seasonId);
    nextDate = await _service.nextMatchDate(season!.seasonId);
    matchesToday = nextDate == null
        ? <FixtureMatch>[]
        : await _service.matchesOnDate(season!.seasonId, nextDate!);
    formation = Formation.parse(await _squads.formationForTeam(userTeamId));
    lineup = await _squads.lineupForTeam(userTeamId);
    if (league != null) {
      final int seasonId = season!.seasonId;
      final int tournamentId = league!.tournamentId;
      standings = await _seasons.standings(seasonId, tournamentId);
      final Map<int, List<GroupTable>> groups = <int, List<GroupTable>>{};
      for (final Tournament tour in cups) {
        if (!tour.isInternational) continue;
        final List<GroupTable> tables = await _seasons.groupTables(
          seasonId,
          tour.tournamentId,
        );
        if (tables.isNotEmpty) groups[tour.tournamentId] = tables;
      }
      cupGroups = groups;
      topScorers = await _seasons.topScorers(seasonId, tournamentId);
      topAssists = await _seasons.topAssists(seasonId, tournamentId);
      topCleanSheets = await _seasons.topCleanSheets(seasonId, tournamentId);
      topRated = await _seasons.topRated(seasonId, tournamentId);
      clubTopScorers = await _seasons.topScorers(
        seasonId,
        tournamentId,
        teamId: userTeamId,
        limit: 5,
      );
      clubTopAssists = await _seasons.topAssists(
        seasonId,
        tournamentId,
        teamId: userTeamId,
        limit: 5,
      );
      clubTopRated = await _seasons.topRated(
        seasonId,
        tournamentId,
        teamId: userTeamId,
        limit: 5,
      );
    }
    inbox = await _messages.latest(teamId: userTeamId);
    unreadCount = inbox.where((Message m) => !m.isRead).length;
    userTeam = await _refs.teamById(userTeamId);
    final Team? refreshed = userTeam;
    if (refreshed != null) {
      teamCache[refreshed.teamId] = refreshed;
    }
    notifyListeners();
  }

  // ------------------------------------------------------------- match days

  /// The user's match on the next date, if any.
  FixtureMatch? get nextUserMatch {
    for (final FixtureMatch m in matchesToday) {
      if (m.homeTeamId == userTeamId || m.awayTeamId == userTeamId) return m;
    }
    return null;
  }

  String competitionLabel(FixtureMatch match) {
    if (match.tournamentId == league?.tournamentId) return 'League';
    for (final Tournament tournament in cups) {
      if (tournament.tournamentId == match.tournamentId) {
        return tournament.isInternational ? 'Intercontinental' : 'Domestic Cup';
      }
    }
    return 'Cup';
  }

  /// Plays the user's live match with full event recording plus the rest of
  /// the matchday, then housekeeping.
  Future<void> startLiveMatch() async {
    final FixtureMatch? mine = nextUserMatch;
    if (mine == null || season == null) return;
    final MatchResult result = await _service.simulateMatch(
      mine,
      recordEvents: true,
    );
    liveSession = LiveMatchSession(
      match: mine,
      result: result,
      homeTeam: teamCache[mine.homeTeamId]!,
      awayTeam: teamCache[mine.awayTeamId]!,
    );
    notifyListeners();
  }

  /// Only quick-simulates the rest of the current matchday (no user match).
  Future<void> playAiMatchday() async {
    if (season == null || nextDate == null) return;
    final int seasonId = season!.seasonId;
    final String date = nextDate!;
    await _service.simulateMatchday(
      seasonId: seasonId,
      date: date,
      skipMatchId: nextUserMatch?.matchId,
    );
    await _rememberMatchday(seasonId, date);
    await _tickAfterMatchday();
  }

  /// Completes a live match: quick-sims the remaining matchday and closes
  /// the live session.
  Future<void> finishLiveMatch() async {
    final FixtureMatch? mine = nextUserMatch;
    final int? seasonId = season?.seasonId;
    final String? date = nextDate;
    if (seasonId != null && date != null) {
      await _service.simulateMatchday(
        seasonId: seasonId,
        date: date,
        skipMatchId: mine?.matchId,
      );
      await _rememberMatchday(seasonId, date);
    }
    liveSession = null;
    await _tickAfterMatchday();
  }

  Future<void> _rememberMatchday(int seasonId, String date) async {
    final List<FixtureMatch> played = await _service.matchesOnDate(
      seasonId,
      date,
      scheduledOnly: false,
    );
    lastMatchday = played.where((FixtureMatch m) => m.isPlayed).toList();
    lastMatchdayTeams = Map<int, Team>.of(teamCache);
  }

  Future<void> _tickAfterMatchday() async {
    if (season == null) return;
    // Cup rounds might be ready to be drawn (domestic and continental).
    for (final Tournament tournament in cups) {
      await _service.maybeScheduleNextCupRound(
        seasonId: season!.seasonId,
        cupTournamentId: tournament.tournamentId,
        teamCache: teamCache,
      );
    }
    week++;
    await _service.weeklyHousekeeping(
      seasonId: season!.seasonId,
      userTeamId: userTeamId,
    );
    await refreshWorld();
    // End of season?
    if (await _service.seasonComplete(season!.seasonId)) {
      busy = true;
      busyStatus = 'Season finished!';
      notifyListeners();
      final Season next = await _service.completeSeason(
        userTeamId: userTeamId,
        onProgress: (String s) {
          busyStatus = s;
          notifyListeners();
        },
      );
      season = next;
      await _deriveCareerContext();
      busy = false;
      await refreshWorld();
    }
  }

  Future<List<FixtureMatch>> seasonFixtures() => season == null
      ? Future<List<FixtureMatch>>.value(<FixtureMatch>[])
      : _seasons.fixturesForSeason(season!.seasonId);

  // ---------------------------------------------------------------- squad

  Future<List<Player>> squadForUser() => _squads.squadForTeam(userTeamId);

  Future<List<SquadStatRow>> squadStatistics() {
    final int? seasonId = season?.seasonId;
    if (seasonId == null) {
      return Future<List<SquadStatRow>>.value(<SquadStatRow>[]);
    }
    return _squads.squadSeasonStats(userTeamId, seasonId);
  }

  Future<Map<int, int>> suspensionsForUser() =>
      _squads.suspensionsForTeam(userTeamId);

  /// Extends a squad player's contract; returns an error message on failure.
  Future<String?> renewContract(int playerId) async {
    if (season == null) return 'No season loaded.';
    final String? error = await _squads.renewContract(
      playerId: playerId,
      teamId: userTeamId,
      currentYear: season!.endYear,
    );
    if (error == null) await refreshWorld();
    return error;
  }

  Future<TrainingState> trainingState() => _squads.trainingStatus(
    teamId: userTeamId,
    seasonId: season?.seasonId ?? 0,
  );

  Future<TrainingOutcome> runTraining(TrainingFocus focus) async {
    if (season == null) {
      return const TrainingOutcome(error: 'No season loaded.');
    }
    final TrainingOutcome outcome = await _squads.runTraining(
      teamId: userTeamId,
      seasonId: season!.seasonId,
      focus: focus,
    );
    if (outcome.ok) await refreshWorld();
    return outcome;
  }

  Future<PlayerDetail?> playerDetail(int playerId) =>
      _squads.playerDetail(playerId, seasonId: season?.seasonId);

  Future<ClubOverview?> clubOverview() => _squads.clubOverview(userTeamId);

  Future<List<ClubTrophy>> clubTrophies() => _seasons.clubTrophies(userTeamId);

  /// Archived-season browsing used by the Table tab history screen.
  Future<List<Season>> allSeasons() => _seasons.allSeasons();

  Future<List<Tournament>> competitionsForSeason(int seasonId) =>
      _seasons.tournamentsForSeason(seasonId);

  Future<List<StandingRow>> standingsForSeason(
    int seasonId,
    int tournamentId,
  ) => _seasons.standings(seasonId, tournamentId);

  Future<List<GroupTable>> groupsForSeason(int seasonId, int tournamentId) =>
      _seasons.groupTables(seasonId, tournamentId);

  Future<ClubHistory> clubHistory() async {
    final List<CareerSeason> seasons = await _seasons.careerHistory(userTeamId);
    final List<PlayerAward> awards = await _seasons.clubAwards(userTeamId);
    return ClubHistory(seasons: seasons, awards: awards);
  }

  /// Expands the stadium one step and refreshes the career world on success.
  Future<String?> expandStadium() async {
    final String? error = await _squads.expandStadium(userTeamId);
    if (error == null) await refreshWorld();
    return error;
  }

  Future<List<TransferRecord>> transferHistory() =>
      _squads.transferHistory(userTeamId);

  /// Saves the tactic used for the next match. A new shape resets the XI
  /// because slot groups change.
  Future<void> setFormation(Formation f) async {
    formation = f;
    await _squads.setFormation(userTeamId, f.name);
    if (lineup.isNotEmpty) {
      lineup = <int, int>{};
      await _squads.clearLineup(userTeamId);
    }
    notifyListeners();
  }

  /// Places [playerId] in [slot]. A player already in another slot swaps with
  /// the occupant, so the XI always stays consistent.
  Future<void> assignLineupSlot(int slot, int playerId) async {
    int? oldSlot;
    for (final MapEntry<int, int> entry in lineup.entries) {
      if (entry.value == playerId) {
        oldSlot = entry.key;
        break;
      }
    }
    final int? displaced = lineup[slot];
    lineup.removeWhere((int key, int value) => value == playerId);
    lineup[slot] = playerId;
    if (displaced != null && oldSlot != null && oldSlot != slot) {
      lineup[oldSlot] = displaced;
    }
    await _squads.saveLineup(userTeamId, lineup);
    notifyListeners();
  }

  Future<void> clearLineupSlot(int slot) async {
    if (lineup.remove(slot) == null) return;
    await _squads.saveLineup(userTeamId, lineup);
    notifyListeners();
  }

  Future<void> clearLineup() async {
    if (lineup.isEmpty) return;
    lineup = <int, int>{};
    await _squads.clearLineup(userTeamId);
    notifyListeners();
  }

  Future<void> toggleSquadStatus(Player p) async {
    final int newStatus = p.squadStatus == t.squadFirstTeam
        ? t.squadReserve
        : t.squadFirstTeam;
    await _squads.setSquadStatus(p.playerId, newStatus);
    await refreshWorld();
  }

  Future<void> makeCaptain(Player p) async {
    await _squads.setCaptain(userTeamId, p.playerId);
    await refreshWorld();
  }

  Future<void> toggleListedForSale(Player p) async {
    final int newMarket = p.marketStatus == t.marketForSale
        ? t.marketActive
        : t.marketForSale;
    await _squads.setMarketStatus(p.playerId, newMarket);
    await refreshWorld();
  }

  Future<List<Map<String, Object?>>> marketPlayers({
    String? search,
    int? positionType,
  }) => _squads.marketPlayers(
    search: search,
    positionType: positionType,
    excludeTeamId: userTeamId,
  );

  Future<String?> buyPlayer(Map<String, Object?> row) async {
    final Player player = Player(
      playerId: row['player_id'] as int,
      name: row['name'] as String,
      age: (row['age'] as int?) ?? 18,
      positionId: (row['position_id'] as int?) ?? 1,
      profile: (row['profile'] as String?) ?? 'D',
      power: (row['power'] as int?) ?? 50,
      potential: (row['potential'] as int?) ?? 50,
      fitness: (row['fitness'] as int?) ?? 100,
      value: (row['value'] as int?) ?? 0,
      salary: (row['salary'] as int?) ?? 0,
      countryId: (row['country_id'] as int?) ?? 0,
      squadStatus: t.squadFirstTeam,
      marketStatus: t.marketForSale,
      statusId: 1,
      isCaptain: false,
      shirtNumber: 0,
      stars: (row['stars'] as int?) ?? 0,
      skillA: 0,
      skillB: 0,
      height: 178,
      championships: null,
    );
    final String? error = await _squads.buyMarketPlayer(
      buyerTeamId: userTeamId,
      player: player,
    );
    if (error == null) {
      await _messages.insert(
        title: 'Transfer complete',
        body:
            '${player.name} joined for ${fmt.money(player.value)}. Contract signed until 3 years.',
        teamId: userTeamId,
        sender: 'Transfer Desk',
      );
      await refreshWorld();
    }
    return error;
  }

  // ---------------------------------------------------------------- inbox

  Future<void> markMessageRead(Message m) async {
    if (m.isRead) return;
    await _messages.markRead(m.messageId);
    unreadCount = max(0, unreadCount - 1);
    notifyListeners();
  }
}

/// A live (watched) match session handed to the match screen.
class LiveMatchSession {
  LiveMatchSession({
    required this.match,
    required this.result,
    required this.homeTeam,
    required this.awayTeam,
  });

  final FixtureMatch match;
  final MatchResult result;
  final Team homeTeam;
  final Team awayTeam;

  /// Shootout kicks once a knockout tie ended level after 90 minutes.
  List<MatchEvent> get shootoutEvents => result.events
      .where((MatchEvent e) => e.type == MatchEvent.shootout)
      .toList();

  bool get decidedOnPenalties => shootoutEvents.isNotEmpty;
}
