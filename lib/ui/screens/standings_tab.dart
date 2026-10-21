import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/models.dart';
import '../../state/career_provider.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'player_detail_sheet.dart';
import 'season_history_sheet.dart';

/// Competition table plus leaderboards. Every domestic and continental
/// competition generated for this career can be selected here.
class StandingsTab extends StatefulWidget {
  const StandingsTab({super.key});

  @override
  State<StandingsTab> createState() => _StandingsTabState();
}

class _StandingsTabState extends State<StandingsTab> {
  int? _selectedId;
  int? _loadedTournamentId;
  int? _loadedSeasonId;
  Future<CompetitionStats>? _stats;

  void _select(CareerProvider game, int id) {
    setState(() {
      _selectedId = id;
      _loadedTournamentId = id;
      _loadedSeasonId = game.season?.seasonId;
      _stats = game.competitionStats(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final CareerProvider game = context.watch<CareerProvider>();
    final List<Tournament> options = <Tournament>[
      if (game.league != null) game.league!,
      ...game.cups,
    ];
    if (options.isEmpty) {
      return const Center(child: Text('No competition available.'));
    }
    final int selectedId =
        options.any(
          (Tournament tournament) => tournament.tournamentId == _selectedId,
        )
        ? _selectedId!
        : options.first.tournamentId;
    final Tournament selected = options.firstWhere(
      (Tournament tournament) => tournament.tournamentId == selectedId,
    );
    if (_stats == null ||
        _loadedTournamentId != selectedId ||
        _loadedSeasonId != game.season?.seasonId) {
      _loadedTournamentId = selectedId;
      _loadedSeasonId = game.season?.seasonId;
      _stats = game.competitionStats(selectedId);
    }
    return FutureBuilder<CompetitionStats>(
      future: _stats,
      builder:
          (BuildContext context, AsyncSnapshot<CompetitionStats> snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final CompetitionStats stats = snapshot.data!;
            return DefaultTabController(
              length: 5,
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              value: selectedId,
                              isExpanded: true,
                              dropdownColor: AppTheme.surfaceCard,
                              items: <DropdownMenuItem<int>>[
                                for (final Tournament tournament in options)
                                  DropdownMenuItem<int>(
                                    value: tournament.tournamentId,
                                    child: Text(
                                      tournament.name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (int? id) {
                                if (id != null) _select(game, id);
                              },
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Season history',
                          icon: const Icon(Icons.history, size: 20),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const SeasonHistoryScreen(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    dividerColor: Colors.transparent,
                    labelColor: AppTheme.accent,
                    unselectedLabelColor: AppTheme.textDim,
                    indicatorColor: AppTheme.accent,
                    tabs: <Widget>[
                      Tab(text: 'Table'),
                      Tab(text: 'Scorers'),
                      Tab(text: 'Assists'),
                      Tab(text: 'Clean sheets'),
                      Tab(text: 'Rating'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: <Widget>[
                        _LeagueTable(
                          game: game,
                          tournament: selected,
                          stats: stats,
                        ),
                        _LeaderList(
                          rows: stats.scorers,
                          metric: 'Goals',
                          userTeamId: game.userTeamId,
                          emptyHint: 'No goals scored yet this season.',
                        ),
                        _LeaderList(
                          rows: stats.assists,
                          metric: 'Assists',
                          userTeamId: game.userTeamId,
                          emptyHint: 'No assists recorded yet this season.',
                        ),
                        _LeaderList(
                          rows: stats.cleanSheets,
                          metric: 'Clean sheets',
                          userTeamId: game.userTeamId,
                          emptyHint:
                              'No clean sheets recorded yet this season.',
                        ),
                        _LeaderList(
                          rows: stats.rated,
                          metric: 'Avg rating',
                          userTeamId: game.userTeamId,
                          emptyHint:
                              'Ratings appear after players complete a match.',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
    );
  }
}

class _LeagueTable extends StatefulWidget {
  const _LeagueTable({
    required this.game,
    required this.tournament,
    required this.stats,
  });

  final CareerProvider game;
  final Tournament tournament;
  final CompetitionStats stats;

  @override
  State<_LeagueTable> createState() => _LeagueTableState();
}

class _LeagueTableState extends State<_LeagueTable> {
  CareerProvider get game => widget.game;

  static const double _rankWidth = 30;
  static const double _statWidth = 26;
  static const double _gdWidth = 34;
  static const double _ptsWidth = 38;

  static const TextStyle _headStyle = TextStyle(
    fontSize: 11,
    color: AppTheme.textDim,
    fontWeight: FontWeight.bold,
  );

  @override
  Widget build(BuildContext context) {
    return widget.stats.groups.isNotEmpty
        ? _groupBody(widget.stats.groups)
        : _leagueBody(widget.stats.standings);
  }

  Widget _leagueBody(List<StandingRow> rows) {
    if (rows.isEmpty) {
      return const Center(
        child: Text('No results yet — play a match to build the table.'),
      );
    }
    return Column(
      children: <Widget>[
        _header(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 20),
            itemCount: rows.length,
            itemBuilder: (BuildContext context, int index) =>
                _row(game, rows[index], index),
          ),
        ),
      ],
    );
  }

  Widget _groupBody(List<GroupTable> groups) {
    if (groups.isEmpty) {
      return const Center(child: Text('No group stage for this cup.'));
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 20),
      children: <Widget>[
        for (int i = 0; i < groups.length; i++) ...<Widget>[
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            color: AppTheme.surfaceCard,
            child: Text(
              'Group ${String.fromCharCode(65 + i)}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          _header(),
          for (int r = 0; r < groups[i].rows.length; r++)
            _row(game, groups[i].rows[r], r, groupStage: true),
        ],
      ],
    );
  }

  Widget _header() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
    color: AppTheme.surfaceCard,
    child: Row(
      children: <Widget>[
        const SizedBox(
          width: _rankWidth,
          child: Text('#', style: _headStyle),
        ),
        const Expanded(child: Text('Club', style: _headStyle)),
        _headCell('P'),
        _headCell('W'),
        _headCell('D'),
        _headCell('L'),
        _headCell('GD', width: _gdWidth),
        _headCell('Pts', width: _ptsWidth),
      ],
    ),
  );

  Widget _headCell(String text, {double width = _statWidth}) => SizedBox(
    width: width,
    child: Text(text, textAlign: TextAlign.center, style: _headStyle),
  );

  Widget _cell(String value, {double width = _statWidth, bool bold = false}) =>
      SizedBox(
        width: width,
        child: Text(
          value,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: bold ? FontWeight.bold : FontWeight.w400,
            color: bold ? Colors.white : null,
          ),
        ),
      );

  Widget _row(
    CareerProvider game,
    StandingRow row,
    int index, {
    bool groupStage = false,
  }) {
    final bool isUser = row.teamId == game.userTeamId;
    final bool promotion = groupStage
        ? index < 2
        : widget.tournament.isLeague &&
              index < widget.tournament.promotionSlots;
    final bool relegation =
        !groupStage &&
        widget.tournament.isLeague &&
        widget.tournament.relegationSpots > 0 &&
        index >=
            widget.stats.standings.length - widget.tournament.relegationSpots;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: isUser ? AppTheme.accentDim.withAlpha(60) : null,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade900, width: 0.5),
        ),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: _rankWidth,
            child: Row(
              children: <Widget>[
                Container(
                  width: 3,
                  height: 14,
                  color: promotion
                      ? AppTheme.accent
                      : relegation
                      ? AppTheme.danger
                      : Colors.transparent,
                ),
                const SizedBox(width: 4),
                Text(
                  '${index + 1}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textDim),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                row.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isUser ? FontWeight.w700 : FontWeight.w400,
                  color: isUser ? AppTheme.accent : Colors.white,
                ),
              ),
            ),
          ),
          _cell('${row.played}'),
          _cell('${row.wins}'),
          _cell('${row.draws}'),
          _cell('${row.losses}'),
          _cell('${row.goalDifference}', width: _gdWidth),
          _cell('${row.points}', width: _ptsWidth, bold: true),
        ],
      ),
    );
  }
}

/// Shared leaderboard list for the four statistical tabs.
class _LeaderList extends StatelessWidget {
  const _LeaderList({
    required this.rows,
    required this.metric,
    required this.userTeamId,
    required this.emptyHint,
  });

  final List<LeaderRow> rows;
  final String metric;
  final int userTeamId;
  final String emptyHint;

  static const double _rankWidth = 28;
  static const double _positionWidth = 38;
  static const double _metricWidth = 72;

  static const TextStyle _headStyle = TextStyle(
    fontSize: 11,
    color: AppTheme.textDim,
    fontWeight: FontWeight.bold,
  );

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(emptyHint, textAlign: TextAlign.center),
        ),
      );
    }
    return Column(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          color: AppTheme.surfaceCard,
          child: Row(
            children: <Widget>[
              const SizedBox(
                width: _rankWidth,
                child: Text('#', style: _headStyle),
              ),
              const SizedBox(
                width: _positionWidth,
                child: Text('POS', style: _headStyle),
              ),
              const SizedBox(width: 8),
              const Expanded(child: Text('Player', style: _headStyle)),
              SizedBox(
                width: _metricWidth,
                child: Text(
                  metric.toUpperCase(),
                  textAlign: TextAlign.right,
                  style: _headStyle.copyWith(fontSize: 9),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 20),
            itemCount: rows.length,
            itemBuilder: (BuildContext context, int index) {
              final LeaderRow row = rows[index];
              final bool isUser = userTeamId != 0 && row.teamId == userTeamId;
              return InkWell(
                onTap: () => showPlayerDetail(context, row.playerId),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isUser ? AppTheme.accentDim.withAlpha(60) : null,
                    border: Border(
                      left: BorderSide(
                        color: isUser ? AppTheme.accent : Colors.transparent,
                        width: 3,
                      ),
                      bottom: BorderSide(
                        color: Colors.grey.shade900,
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: _rankWidth,
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: index < 3
                                ? FontWeight.bold
                                : FontWeight.w400,
                            color: index < 3
                                ? AppTheme.accent
                                : AppTheme.textDim,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: _positionWidth,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: PositionBadge(
                            positionId: row.positionId,
                            profile: row.profile,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Flexible(
                                  child: Text(
                                    row.playerName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isUser
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                      color: isUser ? AppTheme.accent : null,
                                    ),
                                  ),
                                ),
                                if (isUser) ...<Widget>[
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.star,
                                    size: 12,
                                    color: AppTheme.accent,
                                  ),
                                ],
                              ],
                            ),
                            Text(
                              row.clubName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.textDim,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: _metricWidth,
                        child: Text(
                          metric == 'Avg rating'
                              ? row.value.toStringAsFixed(1)
                              : row.display,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
