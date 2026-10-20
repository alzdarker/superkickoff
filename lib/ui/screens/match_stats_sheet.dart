import 'package:flutter/material.dart';

import '../../data/models/models.dart';
import '../../game/match_engine.dart';
import '../../state/career_provider.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Full-time match report: team stats plus the best-rated players.
class MatchStatsSheet extends StatelessWidget {
  const MatchStatsSheet({super.key, required this.session});

  final LiveMatchSession session;

  @override
  Widget build(BuildContext context) {
    final MatchResult result = session.result;
    final List<MatchPlayerRow> best =
        result.playerRows
            .where((MatchPlayerRow row) => row.minutes > 0)
            .toList()
          ..sort(
            (MatchPlayerRow a, MatchPlayerRow b) =>
                b.rating.compareTo(a.rating),
          );

    final int homeYellows = result.playerRows
        .where((MatchPlayerRow row) => row.teamId == session.homeTeam.teamId)
        .fold(0, (int sum, MatchPlayerRow row) => sum + row.yellowCards);
    final int awayYellows = result.playerRows
        .where((MatchPlayerRow row) => row.teamId == session.awayTeam.teamId)
        .fold(0, (int sum, MatchPlayerRow row) => sum + row.yellowCards);
    final int homeReds = result.playerRows
        .where((MatchPlayerRow row) => row.teamId == session.homeTeam.teamId)
        .fold(0, (int sum, MatchPlayerRow row) => sum + row.redCards);
    final int awayReds = result.playerRows
        .where((MatchPlayerRow row) => row.teamId == session.awayTeam.teamId)
        .fold(0, (int sum, MatchPlayerRow row) => sum + row.redCards);

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          children: <Widget>[
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade700,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Full-time statistics',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppTheme.textDim),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  session.homeTeam.abbreviation,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    '${result.homeGoals} - ${result.awayGoals}',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  session.awayTeam.abbreviation,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _possession(result),
            const SizedBox(height: 10),
            _statRow('Shots', result.homeShots, result.awayShots),
            _statRow(
              'Shots on target',
              result.homeShotsOnTarget,
              result.awayShotsOnTarget,
            ),
            _statRow('Saves', result.homeSaves, result.awaySaves),
            _statRow('Yellow cards', homeYellows, awayYellows),
            _statRow('Red cards', homeReds, awayReds),
            const Divider(height: 26),
            const Text(
              'TOP PERFORMERS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDim,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 6),
            for (final MatchPlayerRow row in best.take(8)) _playerRow(row),
          ],
        ),
      ),
    );
  }

  Widget _possession(MatchResult result) {
    final int home = result.homePossession;
    final int away = 100 - home;
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('$home%', style: const TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            const Text(
              'Possession',
              style: TextStyle(fontSize: 11, color: AppTheme.textDim),
            ),
            const Spacer(),
            Text('$away%', style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Row(
            children: <Widget>[
              Expanded(
                flex: home,
                child: Container(height: 7, color: AppTheme.accent),
              ),
              Expanded(
                flex: away,
                child: Container(height: 7, color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statRow(String label, int home, int away) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 38,
            child: Text(
              '$home',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: AppTheme.textDim),
            ),
          ),
          SizedBox(
            width: 38,
            child: Text(
              '$away',
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _playerRow(MatchPlayerRow row) {
    final bool isHome = row.teamId == session.homeTeam.teamId;
    final Team team = isHome ? session.homeTeam : session.awayTeam;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          CrestAvatar(team: team, radius: 11),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  row.playerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${row.minutes}\' · ${row.goals}G ${row.assists}A',
                  style: const TextStyle(fontSize: 10, color: AppTheme.textDim),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.accentDim.withAlpha(120),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              (row.rating / 10).toStringAsFixed(1),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppTheme.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
