import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models/models.dart';
import '../../state/career_provider.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Opens the club hub: overview, finances and stadium in three tabs.
Future<void> showClubHub(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) =>
        const FractionallySizedBox(heightFactor: 0.9, child: ClubHubSheet()),
  );
}

class ClubHubSheet extends StatefulWidget {
  const ClubHubSheet({super.key});

  @override
  State<ClubHubSheet> createState() => _ClubHubSheetState();
}

class _ClubHubSheetState extends State<ClubHubSheet> {
  late Future<ClubOverview?> _future;
  late Future<List<ClubTrophy>> _trophies;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = context.read<CareerProvider>().clubOverview();
    _trophies = context.read<CareerProvider>().clubTrophies();
  }

  void _reload() {
    setState(() {
      _future = context.read<CareerProvider>().clubOverview();
      _trophies = context.read<CareerProvider>().clubTrophies();
    });
  }

  Future<void> _expand() async {
    if (_busy) return;
    setState(() => _busy = true);
    final String? error = await context.read<CareerProvider>().expandStadium();
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppTheme.danger),
      );
      return;
    }
    _reload();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Stadium expanded successfully.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: FutureBuilder<ClubOverview?>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<ClubOverview?> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final ClubOverview? club = snap.data;
          if (club == null) {
            return const Center(child: Text('Club not found.'));
          }
          return _content(club);
        },
      ),
    );
  }

  Widget _content(ClubOverview club) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: <Widget>[
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade700,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: <Widget>[
                CrestAvatar(team: club.team, radius: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        club.team.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${club.countryName} \u00b7 Division ${club.team.division}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  children: <Widget>[
                    Text(
                      '${club.team.power}',
                      style: const TextStyle(
                        fontSize: 26,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.accent,
                      ),
                    ),
                    const Text(
                      'POWER',
                      style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 1,
                        color: AppTheme.textDim,
                      ),
                    ),
                  ],
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
              Tab(text: 'Overview'),
              Tab(text: 'Finances'),
              Tab(text: 'Stadium'),
              Tab(text: 'Honours'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                _overviewTab(club),
                _financesTab(club),
                _stadiumTab(club),
                _honoursTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _overviewTab(ClubOverview club) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              final double width = (c.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  _info('Country', club.countryName, width),
                  _info('Founded', '${club.team.foundedYear}', width),
                  _info('Division', '${club.team.division}', width),
                  _info('Stadium', club.stadiumName, width),
                  _info('City', club.stadiumCity, width),
                  _info('Capacity', _number(club.capacity), width),
                  _info('Coach', club.coachName, width),
                  _info(
                    'Coach age',
                    club.coachAge <= 0 ? '\u2014' : '${club.coachAge}',
                    width,
                  ),
                  _info(
                    'Coach country',
                    club.coachCountry.isEmpty ? '\u2014' : club.coachCountry,
                    width,
                  ),
                  _info('Coach points', '${club.coachPoints}', width),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: <Widget>[
                const Icon(Icons.stadium, color: AppTheme.accent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${club.stadiumName} \u00b7 ${_number(club.capacity)} seats',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _honoursTab() {
    return FutureBuilder<List<ClubTrophy>>(
      future: _trophies,
      builder:
          (BuildContext context, AsyncSnapshot<List<ClubTrophy>> snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final List<ClubTrophy> trophies =
                snapshot.data ?? const <ClubTrophy>[];
            if (trophies.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No trophies yet. Win a league, domestic cup or '
                    'continental competition to fill this cabinet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textDim),
                  ),
                ),
              );
            }
            final Map<String, List<ClubTrophy>> grouped =
                <String, List<ClubTrophy>>{};
            for (final ClubTrophy trophy in trophies) {
              grouped
                  .putIfAbsent(trophy.tournamentName, () => <ClubTrophy>[])
                  .add(trophy);
            }
            final List<MapEntry<String, List<ClubTrophy>>> entries =
                grouped.entries.toList()..sort(
                  (
                    MapEntry<String, List<ClubTrophy>> a,
                    MapEntry<String, List<ClubTrophy>> b,
                  ) => b.value.length.compareTo(a.value.length),
                );
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: <Widget>[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(
                        Icons.emoji_events,
                        color: AppTheme.warn,
                        size: 30,
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '${trophies.length}',
                            style: const TextStyle(
                              fontSize: 26,
                              height: 1,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.warn,
                            ),
                          ),
                          const Text(
                            'TROPHIES',
                            style: TextStyle(
                              fontSize: 9,
                              letterSpacing: 1,
                              color: AppTheme.textDim,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                for (final MapEntry<String, List<ClubTrophy>> entry in entries)
                  _trophyRow(entry.key, entry.value),
              ],
            );
          },
    );
  }

  Widget _trophyRow(String name, List<ClubTrophy> won) {
    final List<int> years = won.map((ClubTrophy t) => t.year).toSet().toList()
      ..sort((int a, int b) => b.compareTo(a));
    final IconData icon = won.first.isInternational
        ? Icons.public
        : won.first.isLeague
        ? Icons.emoji_events
        : Icons.military_tech;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: AppTheme.warn, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  years.join(', '),
                  style: const TextStyle(fontSize: 11, color: AppTheme.textDim),
                ),
              ],
            ),
          ),
          Text(
            'x${won.length}',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppTheme.accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _financesTab(ClubOverview club) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surfaceCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'AVAILABLE BUDGET',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1,
                    color: AppTheme.textDim,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  money(club.team.budget),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.accent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _moneyRow('Squad value', club.squadValue),
          _moneyRow('Wage bill', club.wageBill),
          _moneyRow('Transfer spend', club.transferSpend),
          _moneyRow('Transfer income', club.transferIncome),
          _moneyRow('Net transfers', club.netTransfers, signed: true),
          const Divider(height: 24),
          _moneyRow(
            'Contracts expiring (12m)',
            club.expiringContracts,
            isCount: true,
            warnWhenPositive: true,
          ),
          const SizedBox(height: 12),
          const Text(
            'Wage bill is the combined salary of every player in the squad. '
            'Transfer totals include all seasons.',
            style: TextStyle(fontSize: 11, color: AppTheme.textDim),
          ),
        ],
      ),
    );
  }

  Widget _stadiumTab(ClubOverview club) {
    final bool atMax = club.atMaxCapacity;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _number(club.capacity),
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'Current capacity',
                      style: TextStyle(fontSize: 11, color: AppTheme.textDim),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    _number(
                      club.maxGeneral +
                          club.maxStand +
                          club.maxTerrace +
                          club.maxBoxes,
                    ),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDim,
                    ),
                  ),
                  const Text(
                    'Maximum',
                    style: TextStyle(fontSize: 10, color: AppTheme.textDim),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value:
                  (club.maxGeneral +
                          club.maxStand +
                          club.maxTerrace +
                          club.maxBoxes) <=
                      0
                  ? 0
                  : club.capacity /
                        (club.maxGeneral +
                            club.maxStand +
                            club.maxTerrace +
                            club.maxBoxes),
              minHeight: 8,
              backgroundColor: Colors.grey.shade800,
              color: AppTheme.accent,
            ),
          ),
          const SizedBox(height: 18),
          _tier('General', club.general, club.maxGeneral),
          _tier('Stand', club.stand, club.maxStand),
          _tier('Terrace', club.terrace, club.maxTerrace),
          _tier('Boxes', club.boxes, club.maxBoxes),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surfaceCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  atMax ? 'Stadium fully expanded' : 'Next expansion',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  atMax
                      ? 'Every stand is already at its maximum capacity.'
                      : '+${_number(club.upgradeSeats)} seats for '
                            '${money(club.expansionCost)}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textDim),
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Budget ${money(club.team.budget)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textDim,
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: atMax || _busy ? null : _expand,
                      icon: _busy
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_home_work, size: 17),
                      label: Text(atMax ? 'Maxed out' : 'Expand 10%'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tier(String label, int current, int max) {
    final double progress = max <= 0 ? 0 : (current / max).clamp(0, 1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 66,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppTheme.textDim),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: Colors.grey.shade800,
                color: progress >= 1 ? AppTheme.warn : AppTheme.accent,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 96,
            child: Text(
              '${_number(current)} / ${_number(max)}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _moneyRow(
    String label,
    int value, {
    bool signed = false,
    bool isCount = false,
    bool warnWhenPositive = false,
  }) {
    final Color color = isCount && value > 0 && warnWhenPositive
        ? AppTheme.warn
        : signed
        ? (value >= 0 ? AppTheme.accent : AppTheme.danger)
        : Colors.white;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppTheme.textDim),
            ),
          ),
          Text(
            isCount
                ? '$value'
                : signed
                ? '${value >= 0 ? '+' : '-'}${money(value.abs())}'
                : money(value),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _info(String label, String value, double width) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 9,
                letterSpacing: 0.6,
                color: AppTheme.textDim,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  static String _number(int value) {
    final String digits = value.abs().toString();
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return value < 0 ? '-$out' : out.toString();
  }
}
