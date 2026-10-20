import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/db/schema.dart' as t;
import '../../data/models/models.dart';
import '../../game/formation.dart';
import '../../state/career_provider.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'player_detail_sheet.dart';
import 'training_sheet.dart';

/// Squad management: list players with line-up status, captain pick and
/// transfer listing.
class SquadTab extends StatefulWidget {
  const SquadTab({super.key});

  @override
  State<SquadTab> createState() => _SquadTabState();
}

class _SquadTabState extends State<SquadTab> {
  List<Player>? squad;
  Map<int, int> suspensions = <int, int>{};
  int _loadedWeek = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reload();
  }

  Future<void> _reload() async {
    final CareerProvider game = context.read<CareerProvider>();
    final List<Player> players = await game.squadForUser();
    final Map<int, int> banned = await game.suspensionsForUser();
    if (!mounted) return;
    setState(() {
      squad = players;
      suspensions = banned;
      _loadedWeek = game.week;
    });
  }

  @override
  Widget build(BuildContext context) {
    final CareerProvider game = context.watch<CareerProvider>();
    final List<Player> players = squad ?? const <Player>[];
    if (game.busy) {
      return const Center(child: CircularProgressIndicator());
    }
    if (squad != null && _loadedWeek != game.week) {
      _loadedWeek = game.week;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reload();
      });
    }
    if (players.isEmpty) {
      return const Center(child: Text('Squad not loaded'));
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: players.length + 1,
        itemBuilder: (BuildContext context, int index) {
          if (index == 0) return _overview(game);
          return _playerTile(context, game, players[index - 1]);
        },
      ),
    );
  }

  // ------------------------------------------------------------- overview

  Widget _overview(CareerProvider game) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _formationCard(game),
        _leadersCard(game),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 6, 16, 2),
          child: Text(
            'SQUAD',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDim,
              letterSpacing: 1,
            ),
          ),
        ),
      ],
    );
  }

  Widget _formationCard(CareerProvider game) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(
                  Icons.dashboard_customize,
                  size: 16,
                  color: AppTheme.accent,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Formation',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    await showTrainingSheet(context);
                    if (mounted) await _reload();
                  },
                  icon: const Icon(Icons.fitness_center, size: 16),
                  label: const Text('Train'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                ),
                DropdownButton<Formation>(
                  value: game.formation,
                  isDense: true,
                  dropdownColor: AppTheme.surfaceCard,
                  underline: const SizedBox.shrink(),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.accent,
                    fontWeight: FontWeight.bold,
                  ),
                  items: <DropdownMenuItem<Formation>>[
                    for (final Formation f in Formation.all)
                      DropdownMenuItem<Formation>(
                        value: f,
                        child: Text(f.name),
                      ),
                  ],
                  onChanged: (Formation? f) {
                    if (f != null && f != game.formation) {
                      game.setFormation(f);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                _tacticSlot(
                  '${game.formation.defenders} DEF',
                  const Color(0xFF3B82F6),
                ),
                const SizedBox(width: 6),
                _tacticSlot(
                  '${game.formation.midfielders} MID',
                  const Color(0xFF22C55E),
                ),
                const SizedBox(width: 6),
                _tacticSlot(
                  '${game.formation.forwards} ATT',
                  const Color(0xFFEF4444),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'This shape is used for your next match.',
              style: TextStyle(fontSize: 10, color: AppTheme.textDim),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tacticSlot(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.5)),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
    ),
  );

  Widget _leadersCard(CareerProvider game) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Row(
              children: <Widget>[
                Icon(Icons.leaderboard, size: 16, color: AppTheme.accent),
                SizedBox(width: 6),
                Text(
                  'Club leaders',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _leaderBlock('Best rating', game.clubTopRated, rating: true),
            const Divider(height: 18),
            _leaderBlock('Top scorer', game.clubTopScorers),
            const Divider(height: 18),
            _leaderBlock('Top assists', game.clubTopAssists),
          ],
        ),
      ),
    );
  }

  Widget _leaderBlock(
    String title,
    List<LeaderRow> rows, {
    bool rating = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: AppTheme.textDim,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        if (rows.isEmpty)
          const Text(
            'No matches played yet.',
            style: TextStyle(fontSize: 11, color: AppTheme.textDim),
          )
        else
          for (int i = 0; i < rows.length && i < 3; i++)
            InkWell(
              onTap: () => showPlayerDetail(context, rows[i].playerId),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 16,
                      child: Text(
                        '${i + 1}.',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textDim,
                        ),
                      ),
                    ),
                    PositionBadge(
                      positionId: rows[i].positionId,
                      profile: rows[i].profile,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        rows[i].playerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      rating
                          ? rows[i].value.toStringAsFixed(1)
                          : rows[i].display,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  Widget _playerTile(BuildContext context, CareerProvider game, Player p) {
    final String statusLabel = switch (p.squadStatus) {
      t.squadFirstTeam => 'XI',
      t.squadReserve => 'Res',
      _ => 'Loan',
    };
    final Color statusColor = switch (p.squadStatus) {
      t.squadFirstTeam => AppTheme.accent,
      t.squadReserve => AppTheme.textDim,
      _ => AppTheme.warn,
    };
    return Card(
      child: ListTile(
        onTap: () async {
          await showPlayerDetail(context, p.playerId);
          if (mounted) await _reload();
        },
        leading: SizedBox(
          width: 44,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              PositionBadge(positionId: p.positionId, profile: p.profile),
              const SizedBox(height: 2),
              Text(
                '${p.power}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
        title: Row(
          children: <Widget>[
            if (p.isCaptain)
              const Icon(Icons.star, size: 14, color: AppTheme.accent),
            Flexible(
              child: Text(
                p.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            if (p.marketStatus == t.marketForSale) ...<Widget>[
              const SizedBox(width: 6),
              const Text('🛒', style: TextStyle(fontSize: 11)),
            ],
          ],
        ),
        subtitle: Wrap(
          spacing: 8,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text(
              statusLabel,
              style: TextStyle(fontSize: 10, color: statusColor),
            ),
            if ((suspensions[p.playerId] ?? 0) > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: AppTheme.danger.withValues(alpha: 0.5),
                  ),
                ),
                child: Text(
                  'SUSP ${suspensions[p.playerId]}',
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.danger,
                  ),
                ),
              ),
            Text(
              '${p.age}y · ${money(p.value)} · ${money(p.salary)}/w',
              style: const TextStyle(fontSize: 11, color: AppTheme.textDim),
            ),
            Stars(value: p.stars, size: 10),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            FitnessBar(value: p.fitness),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 18),
              onSelected: (String action) async {
                switch (action) {
                  case 'lineup':
                    await game.toggleSquadStatus(p);
                    break;
                  case 'captain':
                    await game.makeCaptain(p);
                    break;
                  case 'market':
                    await game.toggleListedForSale(p);
                    break;
                }
                await _reload();
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'lineup',
                  child: Text('Toggle squad role (Reserve / First team)'),
                ),
                const PopupMenuItem<String>(
                  value: 'captain',
                  child: Text('Make captain'),
                ),
                PopupMenuItem<String>(
                  value: 'market',
                  child: Text(
                    p.marketStatus == t.marketForSale
                        ? 'Remove from market'
                        : 'List for sale',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
