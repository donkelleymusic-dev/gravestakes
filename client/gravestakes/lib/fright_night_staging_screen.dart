// fright_night_staging_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flame/game.dart';
import 'game.dart';
import 'match_summary_overlay.dart';

class FrightNightStagingScreen extends StatefulWidget {
  final String eventId;
  final String chaosMode;
  final bool isLeader;

  const FrightNightStagingScreen({
    Key? key,
    required this.eventId,
    required this.chaosMode,
    required this.isLeader,
  }) : super(key: key);

  @override
  State<FrightNightStagingScreen> createState() => _FrightNightStagingScreenState();
}

class _FrightNightStagingScreenState extends State<FrightNightStagingScreen> {
  final supabase = Supabase.instance.client;
  RealtimeChannel? _stagingChannel;

  int _currentRound = 0;
  int _maxRounds = 10;
  String _eventStatus = 'staging';
  List<Map<String, dynamic>> _attendees = [];
  bool _isLoading = true;
  bool _isInMatch = false; // Prevents double-pushing if broadcast & DB change arrive together

  @override
  void initState() {
    super.initState();
    _loadEventState();
    _subscribeToStaging();
  }

  @override
  void dispose() {
    _stagingChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadEventState() async {
    try {
      final eventRes = await supabase
          .from('guild_fright_nights')
          .select('current_round, max_rounds, event_status')
          .eq('id', widget.eventId)
          .single();

      final attendeesRes = await supabase
          .from('fright_night_rsvps')
          .select('status, cumulative_score, user_id, profiles(username)')
          .eq('event_id', widget.eventId);

      if (mounted) {
        setState(() {
          _currentRound = eventRes['current_round'] ?? 0;
          _maxRounds = eventRes['max_rounds'] ?? 10;
          _eventStatus = eventRes['event_status'] ?? 'staging';
          _attendees = List<Map<String, dynamic>>.from(attendeesRes);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading staging state: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load event data. It may have expired.'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _subscribeToStaging() {
    _stagingChannel = supabase.channel('room_fright_${widget.eventId}')
      .onBroadcast(
        event: 'launch_round_match',
        callback: (payload) {
          if (widget.isLeader || _isInMatch) return; // Leader already entered locally
          final roomId = payload['room_id'] as String;
          final round = (payload['round'] as num).toInt();
          _enterMatch(roomId, round);
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'guild_fright_nights',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: widget.eventId,
        ),
        callback: (payload) {
          _loadEventState();
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'fright_night_rsvps',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'event_id',
          value: widget.eventId,
        ),
        callback: (payload) {
          _loadEventState();
        },
      )
      .subscribe();
  }

  Future<void> _launchNextRoundLeader() async {
    if (_isInMatch) return;
    int nextRound = _currentRound + 1;
    if (nextRound > _maxRounds) return;

    final String roundRoomId = 'fright_${widget.eventId}_round_$nextRound';

    try {
      await supabase.from('guild_fright_nights').update({
        'current_round': nextRound,
        'event_status': 'in_match',
      }).eq('id', widget.eventId);

      await _stagingChannel?.sendBroadcastMessage(
        event: 'launch_round_match',
        payload: {
          'room_id': roundRoomId,
          'round': nextRound,
        },
      );

      _enterMatch(roundRoomId, nextRound);
    } catch (e) {
      debugPrint('Failed to launch round: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to launch round: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _enterMatch(String roomId, int roundNumber) async {
    if (_isInMatch) return;
    _isInMatch = true;

    final gameInstance = GraveStakesGame(
      roomId: roomId,
      matchMode: 'fright_night',
      chaosModifier: widget.chaosMode,
      // FIXED: Allow up to 16 human players (guild + Reddit guest passes) in the same room!
      targetPlayers: 16,
    );

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          body: GameWidget<GraveStakesGame>(
            game: gameInstance,
            loadingBuilder: (context) => Container(
              color: Colors.black,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.redAccent),
                    const SizedBox(height: 20),
                    Text(
                      'LOADING ROUND $roundNumber / $_maxRounds...',
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2.0, fontFamily: 'Courier'),
                    ),
                  ],
                ),
              ),
            ),
            overlayBuilderMap: {
              'summary': (BuildContext context, GraveStakesGame game) => MatchSummaryOverlay(game: game),
              'searching': (BuildContext context, GraveStakesGame game) => SearchingOverlay(game: game),
              'countdown': (BuildContext context, GraveStakesGame game) => CountdownOverlay(game: game),
            },
          ),
        ),
      ),
    );

    _isInMatch = false;

    // FIXED: Persist this round's score to cumulative_score in fright_night_rsvps!
    final userId = supabase.auth.currentUser?.id;
    if (userId != null && gameInstance.player.score > 0) {
      try {
        final existing = await supabase
            .from('fright_night_rsvps')
            .select('cumulative_score')
            .eq('event_id', widget.eventId)
            .eq('user_id', userId)
            .maybeSingle();
        final int prevScore = (existing?['cumulative_score'] as num?)?.toInt() ?? 0;
        await supabase.from('fright_night_rsvps').upsert({
          'event_id': widget.eventId,
          'user_id': userId,
          'status': existing != null ? (existing['status'] ?? 'attending') : 'guest_pass',
          'cumulative_score': prevScore + gameInstance.player.score,
        });
      } catch (e) {
        debugPrint('Error updating Fright Night cumulative score: $e');
      }
    }

    // FIXED: If leader returns from the match, set event_status back to 'staging' (or 'completed' after final round)
    if (widget.isLeader) {
      try {
        final String nextStatus = roundNumber >= _maxRounds ? 'completed' : 'staging';
        await supabase.from('guild_fright_nights').update({
          'event_status': nextStatus,
        }).eq('id', widget.eventId);
      } catch (e) {}
    }

    if (mounted) {
      _loadEventState();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sortedAttendees = List<Map<String, dynamic>>.from(_attendees)
      ..sort((a, b) => (b['cumulative_score'] ?? 0).compareTo(a['cumulative_score'] ?? 0));

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        title: Text('FRIGHT NIGHT STAGING [${widget.chaosMode.toUpperCase()}]', style: const TextStyle(color: Colors.redAccent, fontSize: 14, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.red))
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('TOURNAMENT PROGRESS', style: TextStyle(color: Colors.white54, fontSize: 10, fontFamily: 'Courier')),
                            const SizedBox(height: 4),
                            Text('ROUND $_currentRound OF $_maxRounds', style: const TextStyle(color: Colors.amberAccent, fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: _eventStatus == 'in_match' ? Colors.red[900] : Colors.green[900],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(_eventStatus.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('GUILD STANDINGS', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, letterSpacing: 1.2, fontFamily: 'Courier')),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[950],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: ListView.builder(
                        itemCount: sortedAttendees.length,
                        itemBuilder: (context, index) {
                          final attendee = sortedAttendees[index];
                          final profile = attendee['profiles'] ?? {};
                          final username = profile['username'] ?? 'Mercenary';
                          final score = attendee['cumulative_score'] ?? 0;
                          final status = attendee['status'] ?? 'pending';

                          return ListTile(
                            dense: true,
                            leading: Text('#${index + 1}', style: TextStyle(color: index == 0 ? Colors.amberAccent : Colors.white54, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
                            title: Text(username, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            subtitle: Text('Status: ${status.toUpperCase()}', style: const TextStyle(color: Colors.white54, fontSize: 10)),
                            trailing: Text('$score Souls', style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (widget.isLeader)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[900],
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: Colors.amberAccent, width: 1.5),
                      ),
                      onPressed: (_currentRound < _maxRounds && _eventStatus != 'in_match') ? _launchNextRoundLeader : null,
                      icon: const Icon(Icons.bolt, color: Colors.amberAccent),
                      label: Text(
                        _currentRound >= _maxRounds
                            ? 'TOURNAMENT COMPLETED'
                            : (_currentRound == 0 ? 'LAUNCH ROUND 1' : 'LAUNCH ROUND ${_currentRound + 1}'),
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                      ),
                    )
                  else if (_eventStatus == 'in_match' && _currentRound > 0)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange[900],
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: () => _enterMatch('fright_${widget.eventId}_round_$_currentRound', _currentRound),
                      icon: const Icon(Icons.login, color: Colors.white),
                      label: Text('JOIN ROUND $_currentRound IN PROGRESS', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    )
                  else
                    const Center(
                      child: Text(
                        'Waiting for Guild Leader to launch the next round...',
                        style: TextStyle(color: Colors.white54, fontStyle: FontStyle.italic, fontFamily: 'Courier'),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class SearchingOverlay extends StatelessWidget {
  final GraveStakesGame game;
  const SearchingOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.purpleAccent),
            const SizedBox(height: 24),
            Text(
              'WAITING FOR CHALLENGERS...\n(${game.matchMode.toUpperCase()})',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2),
            ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.redAccent),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: () => Navigator.of(context).pop(), 
              icon: const Icon(Icons.exit_to_app, color: Colors.redAccent),
              label: const Text('LEAVE LOBBY', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

class CountdownOverlay extends StatelessWidget {
  final GraveStakesGame game;
  const CountdownOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black45,
      child: Center(
        child: Text(
          game.countdownTimer.ceil().toString(),
          style: const TextStyle(
            color: Colors.redAccent, 
            fontSize: 120, 
            fontWeight: FontWeight.bold,
            shadows: [Shadow(color: Colors.black, blurRadius: 10)]
          ),
        ),
      ),
    );
  }
}