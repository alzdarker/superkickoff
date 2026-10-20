import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models/models.dart';
import '../../game/match_engine.dart';
import '../../state/career_provider.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'match_stats_sheet.dart';
import 'matchday_results_sheet.dart';

/// Live match viewer: the result is pre-simulated by the engine and revealed
/// minute by minute, exactly like Superkickoff's timeline games.
class MatchScreen extends StatefulWidget {
  const MatchScreen({super.key});

  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen> {
  Timer? _ticker;
  int displayedMinute = 0;
  double speed = 1;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void startClock() {
    _ticker?.cancel();
    _ticker = Timer.periodic(Duration(milliseconds: (400 / speed).round()), (
      Timer t,
    ) {
      final LiveMatchSession? session = context
          .read<CareerProvider>()
          .liveSession;
      if (session == null) return;
      if (displayedMinute < 90) {
        setState(() => displayedMinute++);
      } else {
        t.cancel();
      }
    });
  }

  void finishInstantly() {
    setState(() => displayedMinute = 90);
    _ticker?.cancel();
  }

  void showStats(LiveMatchSession session) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.88,
        child: MatchStatsSheet(session: session),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final CareerProvider game = context.watch<CareerProvider>();
    final LiveMatchSession? session = game.liveSession;
    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (displayedMinute == 0) {
      // First build after session set: kick-off.
      scheduleMicrotask(startClock);
    }
    final int homeGoals = _goalsUpTo(session, true);
    final int awayGoals = _goalsUpTo(session, false);
    final List<MatchEvent> shown = session.result.events
        .where((MatchEvent e) => e.minute <= displayedMinute)
        .toList();
    final List<MatchEvent> kicks = displayedMinute >= 90
        ? session.shootoutEvents
        : <MatchEvent>[];
    final bool finished = displayedMinute >= 90;

    return Scaffold(
      appBar: AppBar(title: const Text('Match Day')),
      body: Column(
        children: <Widget>[
          _scoreBoard(
            session,
            game.competitionLabel(session.match),
            homeGoals,
            awayGoals,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: <Widget>[
                for (final MatchEvent e in shown) _eventTile(e, session),
                if (kicks.isNotEmpty) _shootoutSection(session, kicks),
              ],
            ),
          ),
          _controls(finished, session, game),
        ],
      ),
    );
  }

  int _goalsUpTo(LiveMatchSession session, bool home) {
    int goals = 0;
    for (final MatchEvent e in session.result.events) {
      if (e.minute > displayedMinute) break;
      if (e.type == MatchEvent.goal ||
          e.type == MatchEvent.ownGoal ||
          e.type == MatchEvent.penaltyScored) {
        final bool benefitsHome = e.type == MatchEvent.ownGoal
            ? !e.isHome
            : e.isHome;
        if (benefitsHome == home) goals++;
      }
    }
    return goals;
  }

  Widget _scoreBoard(
    LiveMatchSession session,
    String competitionLabel,
    int homeGoals,
    int awayGoals,
  ) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade900),
      ),
      child: Column(
        children: <Widget>[
          Text(
            competitionLabel.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              letterSpacing: .7,
              color: AppTheme.textDim,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  children: <Widget>[
                    Text(
                      session.homeTeam.abbreviation,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      session.homeTeam.name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textDim,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                children: <Widget>[
                  Text(
                    '$homeGoals - $awayGoals',
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (displayedMinute >= 90 && session.decidedOnPenalties)
                    Text(
                      'Pens ${_shootoutScore(session, true)}-'
                      '${_shootoutScore(session, false)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.warn,
                      ),
                    ),
                  Text(
                    '$displayedMinute\'',
                    style: TextStyle(
                      color: AppTheme.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Expanded(
                child: Column(
                  children: <Widget>[
                    Text(
                      session.awayTeam.abbreviation,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      session.awayTeam.name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textDim,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  int _shootoutScore(LiveMatchSession session, bool home) {
    int score = 0;
    for (final MatchEvent e in session.shootoutEvents) {
      if (e.isHome == home && e.detail?.startsWith('scored') == true) score++;
    }
    return score;
  }

  /// Penalty shootout kicks listed after normal time.
  Widget _shootoutSection(LiveMatchSession session, List<MatchEvent> kicks) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 16, 4, 6),
          child: Text(
            'PENALTY SHOOTOUT',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1,
              color: AppTheme.textDim,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        for (final MatchEvent e in kicks)
          ListTile(
            dense: true,
            leading: Icon(
              e.detail?.startsWith('scored') == true
                  ? Icons.check_circle
                  : Icons.cancel,
              size: 18,
              color: e.detail?.startsWith('scored') == true
                  ? AppTheme.accent
                  : AppTheme.danger,
            ),
            title: Text(
              '${e.playerName ?? 'Taker'}  ·  '
              '${e.detail?.startsWith('scored') == true ? 'scored' : 'missed'}',
              style: const TextStyle(fontSize: 13),
            ),
            trailing: Text(
              (e.isHome ? session.homeTeam : session.awayTeam).abbreviation,
              style: const TextStyle(color: AppTheme.textDim, fontSize: 11),
            ),
          ),
      ],
    );
  }

  Widget _eventTile(MatchEvent e, LiveMatchSession session) {
    final (String label, IconData icon, Color color) = switch (e.type) {
      MatchEvent.goal => ('Goal', Icons.sports_soccer, AppTheme.accent),
      MatchEvent.penaltyScored => (
        'Penalty scored',
        Icons.sports_handball,
        AppTheme.accent,
      ),
      MatchEvent.penaltyMissed => (
        'Penalty missed',
        Icons.sports_handball,
        AppTheme.warn,
      ),
      MatchEvent.ownGoal => ('Own goal', Icons.error_outline, AppTheme.danger),
      MatchEvent.save => ('Save', Icons.pan_tool, AppTheme.textDim),
      MatchEvent.yellow => ('Yellow card', Icons.square, AppTheme.warn),
      MatchEvent.red => ('Red card', Icons.square, AppTheme.danger),
      MatchEvent.injury => ('Injury', Icons.medical_services, AppTheme.danger),
      MatchEvent.subIn => (
        'Substitution in',
        Icons.swap_horiz,
        AppTheme.textDim,
      ),
      MatchEvent.subOut => (
        'Substitution out',
        Icons.swap_horiz,
        AppTheme.textDim,
      ),
      MatchEvent.varCheck => ('VAR check', Icons.monitor, AppTheme.textDim),
      MatchEvent.varGoalDisallowed => (
        'Goal disallowed',
        Icons.videocam_off,
        AppTheme.danger,
      ),
      _ => (e.type, Icons.info, AppTheme.textDim),
    };
    final Team team = e.isHome ? session.homeTeam : session.awayTeam;
    return ListTile(
      dense: true,
      leading: Icon(icon, color: color, size: 20),
      title: Text(
        '${e.minute}\'  $label${e.playerName != null ? '  ·  ${e.playerName}' : ''}',
        style: const TextStyle(fontSize: 13),
      ),
      trailing: Text(
        team.abbreviation,
        style: const TextStyle(color: AppTheme.textDim, fontSize: 11),
      ),
    );
  }

  Widget _controls(
    bool finished,
    LiveMatchSession session,
    CareerProvider game,
  ) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: finished
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      statChip(
                        session.decidedOnPenalties
                            ? 'Penalties'
                            : 'Final score',
                        session.decidedOnPenalties
                            ? '${_shootoutScore(session, true)}-'
                                  '${_shootoutScore(session, false)}'
                            : 'FT',
                        color: AppTheme.accent,
                      ),
                      const SizedBox(width: 16),
                      statChip(
                        'Revenue',
                        money(session.result.revenue),
                        icon: Icons.payments,
                      ),
                      const SizedBox(width: 16),
                      statChip(
                        'Attendance',
                        '${session.result.attendanceGeneral + session.result.attendanceStand + session.result.attendanceTerrace + session.result.attendanceBoxes}',
                        icon: Icons.groups,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      OutlinedButton.icon(
                        onPressed: () => showStats(session),
                        icon: const Icon(Icons.bar_chart, size: 16),
                        label: const Text('Stats'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: () async {
                            await game.finishLiveMatch();
                            if (!mounted) return;
                            await showMatchdayResults(
                              context,
                              matches: game.lastMatchday,
                              teams: game.lastMatchdayTeams,
                              userTeamId: game.userTeamId,
                              competitionLabel: game.competitionLabel,
                              date: session.match.date,
                            );
                            if (mounted) Navigator.of(context).pop();
                          },
                          child: const Text('Continue'),
                        ),
                      ),
                    ],
                  ),
                ],
              )
            : Row(
                children: <Widget>[
                  for (final double s in <double>[1, 2, 4])
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () => setState(() {
                          speed = s;
                          startClock();
                        }),
                        icon: Icon(
                          speed == s ? Icons.check : Icons.speed,
                          size: 14,
                        ),
                        label: Text('${s}x'),
                      ),
                    ),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: finishInstantly,
                      icon: const Icon(Icons.skip_next, size: 16),
                      label: const Text('To end'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
