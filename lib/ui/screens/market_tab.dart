import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models/models.dart';
import '../../state/career_provider.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'player_detail_sheet.dart';

/// Full-page transfer market: listed players plus the club's transfer history.
class MarketTab extends StatefulWidget {
  const MarketTab({super.key});

  @override
  State<MarketTab> createState() => _MarketTabState();
}

class _MarketTabState extends State<MarketTab> {
  final TextEditingController _search = TextEditingController();
  List<Map<String, Object?>> players = <Map<String, Object?>>[];
  int? positionFilter;
  bool loading = true;
  String? error;
  int _historyVersion = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final CareerProvider game = context.read<CareerProvider>();
    final List<Map<String, Object?>> list = await game.marketPlayers(
      search: _search.text.trim().isEmpty ? null : _search.text.trim(),
      positionType: positionFilter,
    );
    if (!mounted) return;
    setState(() {
      players = list;
      loading = false;
    });
  }

  Future<void> _confirmBuy(Map<String, Object?> row) async {
    final CareerProvider game = context.read<CareerProvider>();
    final int value = (row['value'] as int?) ?? 0;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('Sign ${row['name']}?'),
        content: Text(
          'Transfer fee: ${money(value)}\n'
          'Club: ${row['club_name'] ?? 'Free agent'}\n'
          'Power: ${row['power']} / Potential: ${row['potential']}\n'
          'Your budget: ${money(game.userTeam?.budget ?? 0)}',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Buy'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final String? failure = await game.buyPlayer(row);
    if (!mounted) return;
    setState(() {
      error = failure;
      if (failure == null) _historyVersion++;
    });
    if (failure == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${row['name']} joined your squad!')),
      );
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final CareerProvider game = context.watch<CareerProvider>();
    return DefaultTabController(
      length: 2,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
            child: Row(
              children: <Widget>[
                const Text(
                  'Transfer Market',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Spacer(),
                Text(
                  'Budget ${money(game.userTeam?.budget ?? 0)}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.accent),
                ),
              ],
            ),
          ),
          const TabBar(
            labelColor: AppTheme.accent,
            unselectedLabelColor: AppTheme.textDim,
            indicatorColor: AppTheme.accent,
            dividerColor: Colors.white10,
            tabs: <Widget>[
              Tab(text: 'Listed players'),
              Tab(text: 'Transfer history'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                _listedTab(),
                _TransferHistory(key: ValueKey<int>(_historyVersion)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _listedTab() {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _load(),
            decoration: InputDecoration(
              hintText: 'Search players...',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _search.clear();
                  _load();
                },
              ),
            ),
          ),
        ),
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: <Widget>[
              for (final (String label, int? type) in <(String, int?)>[
                ('All', null),
                ('GK', 1),
                ('DEF', 2),
                ('MID', 3),
                ('ATT', 4),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: positionFilter == type,
                    onSelected: (_) {
                      setState(() => positionFilter = type);
                      _load();
                    },
                  ),
                ),
            ],
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              error!,
              style: const TextStyle(color: AppTheme.danger, fontSize: 11),
            ),
          ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : players.isEmpty
              ? const Center(
                  child: Text(
                    'No players listed for sale right now.\n'
                    'Clubs relist players as the season advances.',
                    textAlign: TextAlign.center,
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 20),
                    itemCount: players.length,
                    itemBuilder: (BuildContext context, int index) {
                      final Map<String, Object?> row = players[index];
                      return _PlayerMarketCard(
                        row: row,
                        onBuy: () => _confirmBuy(row),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _PlayerMarketCard extends StatelessWidget {
  const _PlayerMarketCard({required this.row, required this.onBuy});

  final Map<String, Object?> row;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: () => showPlayerDetail(context, row['player_id'] as int),
        leading: PositionBadge(
          positionId: (row['position_id'] as int?) ?? 1,
          profile: row['profile'] as String?,
        ),
        title: Text(
          '${row['name']}  ${row['power']}',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${row['age']}y · ${row['club_name']} · '
          '${money((row['value'] as int?) ?? 0)}',
          style: const TextStyle(fontSize: 11),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.add_shopping_cart, color: AppTheme.accent),
          onPressed: onBuy,
        ),
      ),
    );
  }
}

class _TransferHistory extends StatefulWidget {
  const _TransferHistory({super.key});

  @override
  State<_TransferHistory> createState() => _TransferHistoryState();
}

class _TransferHistoryState extends State<_TransferHistory> {
  late Future<List<TransferRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<CareerProvider>().transferHistory();
  }

  Future<void> _reload() async {
    setState(() {
      _future = context.read<CareerProvider>().transferHistory();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final CareerProvider game = context.watch<CareerProvider>();
    return FutureBuilder<List<TransferRecord>>(
      future: _future,
      builder:
          (BuildContext context, AsyncSnapshot<List<TransferRecord>> snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final List<TransferRecord> records =
                snap.data ?? const <TransferRecord>[];
            if (records.isEmpty) {
              return RefreshIndicator(
                onRefresh: _reload,
                child: ListView(
                  children: const <Widget>[
                    SizedBox(height: 90),
                    Icon(Icons.swap_horiz, size: 42, color: AppTheme.textDim),
                    SizedBox(height: 10),
                    Center(
                      child: Text(
                        'No transfers yet.\n'
                        'Players you buy or sell will show up here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.textDim),
                      ),
                    ),
                  ],
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: _reload,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 20),
                itemCount: records.length,
                separatorBuilder: (_, _) => const SizedBox(height: 0),
                itemBuilder: (BuildContext context, int index) {
                  final TransferRecord r = records[index];
                  final bool incoming = r.toTeamId == game.userTeamId;
                  return Card(
                    child: ListTile(
                      onTap: () => showPlayerDetail(context, r.playerId),
                      leading: CircleAvatar(
                        radius: 17,
                        backgroundColor:
                            (incoming ? AppTheme.accent : AppTheme.warn)
                                .withValues(alpha: 0.18),
                        child: Icon(
                          incoming ? Icons.south_west : Icons.north_east,
                          size: 18,
                          color: incoming ? AppTheme.accent : AppTheme.warn,
                        ),
                      ),
                      title: Text(
                        r.playerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '${incoming ? 'From' : 'To'} '
                        '${incoming ? r.fromTeamName : r.toTeamName} · '
                        '${shortDate(r.date)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Text(
                        r.value <= 0
                            ? 'Free'
                            : '${incoming ? '-' : '+'}${money(r.value)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: incoming ? AppTheme.warn : AppTheme.accent,
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
    );
  }
}
