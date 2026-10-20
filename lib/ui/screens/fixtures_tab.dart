import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/models.dart';
import '../../state/career_provider.dart';
import '../theme.dart';
import 'knockout_bracket_sheet.dart';

/// Season calendar grouped by match week with results and upcoming games.
class FixturesTab extends StatefulWidget {
  const FixturesTab({super.key});

  @override
  State<FixturesTab> createState() => _FixturesTabState();
}

class _FixturesTabState extends State<FixturesTab> {
  List<FixtureMatch>? fixtures;
  Map<int, String> tournamentNames = <int, String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  Future<void> _load() async {
    final CareerProvider game = context.read<CareerProvider>();
    if (game.season == null) return;
    final List<FixtureMatch> list = await game.seasonFixtures();
    if (!mounted) return;
    setState(() {
      fixtures = list;
      tournamentNames = <int, String>{
        for (final Tournament tour in game.cups) tour.tournamentId: tour.name,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final CareerProvider game = context.watch<CareerProvider>();
    final List<FixtureMatch> list = fixtures ?? const <FixtureMatch>[];
    if (list.isEmpty) {
      return const Center(child: Text('No fixtures yet'));
    }
    final int leagueId = game.league?.tournamentId ?? 0;
    final Map<int, List<FixtureMatch>> knockoutMatches =
        <int, List<FixtureMatch>>{};
    for (final FixtureMatch match in list) {
      if (match.tournamentId == leagueId || match.groupId != null) continue;
      knockoutMatches
          .putIfAbsent(match.tournamentId, () => <FixtureMatch>[])
          .add(match);
    }
    final Map<int, int> totalRounds = <int, int>{
      for (final MapEntry<int, List<FixtureMatch>> entry
          in knockoutMatches.entries)
        entry.key: knockoutTotalRounds(entry.value),
    };

    // Group by tournament + round.
    final Map<String, List<FixtureMatch>> groups =
        <String, List<FixtureMatch>>{};
    for (final FixtureMatch m in list) {
      final bool isLeague = m.tournamentId == leagueId;
      final String stage = m.groupId != null
          ? 'Group ${String.fromCharCode(64 + m.groupId!)} · '
                'Matchday ${m.round}'
          : knockoutRoundName(m.phase, totalRounds[m.tournamentId] ?? 1);
      final String key = isLeague
          ? '${game.league?.name ?? 'League'} · Round ${m.round}'
          : '${tournamentNames[m.tournamentId] ?? 'Cup'} · $stage';
      groups.putIfAbsent(key, () => <FixtureMatch>[]).add(m);
    }
    final List<String> keys = groups.keys.toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 20),
        itemCount: keys.length,
        itemBuilder: (BuildContext context, int index) {
          final String key = keys[index];
          final List<FixtureMatch> group = groups[key]!
            ..sort(
              (FixtureMatch a, FixtureMatch b) =>
                  (a.date ?? '').compareTo(b.date ?? ''),
            );
          final DateTime? date = DateTime.tryParse(group.first.date ?? '');
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 13, 12, 4),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '$key  ·  ${date == null ? '' : _formatDate(date)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: group.first.tournamentId == leagueId
                              ? AppTheme.accent
                              : AppTheme.warn,
                        ),
                      ),
                    ),
                    if (knockoutMatches[group.first.tournamentId] != null &&
                        group.first.phase == 1)
                      TextButton.icon(
                        onPressed: () {
                          Tournament? tournament;
                          for (final Tournament cup in game.cups) {
                            if (cup.tournamentId == group.first.tournamentId) {
                              tournament = cup;
                              break;
                            }
                          }
                          if (tournament == null) return;
                          showKnockoutBracket(
                            context,
                            tournament: tournament,
                            matches: knockoutMatches[tournament.tournamentId]!,
                            teams: game.teamCache,
                          );
                        },
                        icon: const Icon(Icons.account_tree_outlined, size: 15),
                        label: const Text('Bracket'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          textStyle: const TextStyle(fontSize: 11),
                        ),
                      ),
                  ],
                ),
              ),
              for (final FixtureMatch m in group) _fixtureRow(game, m),
            ],
          );
        },
      ),
    );
  }

  Widget _fixtureRow(CareerProvider game, FixtureMatch m) {
    final Team? home = game.teamCache[m.homeTeamId];
    final Team? away = game.teamCache[m.awayTeamId];
    final bool involvesUser =
        m.homeTeamId == game.userTeamId || m.awayTeamId == game.userTeamId;
    final bool played = m.isPlayed;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: involvesUser
            ? AppTheme.accentDim.withAlpha(70)
            : AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            game.competitionLabel(m).toUpperCase(),
            style: const TextStyle(
              fontSize: 9,
              letterSpacing: .6,
              color: AppTheme.textDim,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  home?.name ?? '?',
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: involvesUser
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
              ),
              Container(
                width: 66,
                alignment: Alignment.center,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      played
                          ? '${m.homeGoals ?? 0} - ${m.awayGoals ?? 0}'
                          : 'vs',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: played ? 14 : 11,
                        color: played ? Colors.white : AppTheme.textDim,
                      ),
                    ),
                    if ((m.penaltyHomeGoals ?? 0) > 0 ||
                        (m.penaltyAwayGoals ?? 0) > 0)
                      Text(
                        'pens ${m.penaltyHomeGoals}-${m.penaltyAwayGoals}',
                        style: const TextStyle(
                          fontSize: 8,
                          color: AppTheme.warn,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Text(
                  away?.name ?? '?',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: involvesUser
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime d) {
    const List<String> months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }
}
