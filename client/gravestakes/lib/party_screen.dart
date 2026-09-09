import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flame/game.dart';
import 'game.dart';
import 'match_summary_overlay.dart'; // Required for the summary screen

class PartyScreen extends StatefulWidget {
  const PartyScreen({super.key});

  @override
  State<PartyScreen> createState() => _PartyScreenState();
}

class _PartyScreenState extends State<PartyScreen> {
  final supabase = Supabase.instance.client;

  bool _isLoading = true;
  Map<String, dynamic>? _currentParty;
  List<Map<String, dynamic>> _partyMembers = [];
  List<Map<String, dynamic>> _friends = [];
  
  RealtimeChannel? _lobbyChannel;

  @override
  void initState() {
    super.initState();
    _loadPartyAndFriends();
  }

  @override
  void dispose() {
    _lobbyChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadPartyAndFriends() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final membership = await supabase
          .from('party_members')
          .select('party_id, parties(*)')
          .eq('user_id', user.id)
          .maybeSingle();

      if (membership != null) {
        _currentParty = membership['parties'];

        final membersRes = await supabase
            .from('party_members')
            .select('user_id, status, profiles(username, level)')
            .eq('party_id', _currentParty!['id']);

        _partyMembers = List<Map<String, dynamic>>.from(membersRes);
        
        _listenToPartyLobby(_currentParty!['id']);
      } else {
        _currentParty = null;
        _partyMembers = [];
        _lobbyChannel?.unsubscribe();
      }

      final friendshipsRes = await supabase
          .from('friendships')
          .select('user_id, friend_id')
          .eq('status', 'accepted')
          .or('user_id.eq.${user.id},friend_id.eq.${user.id}');

      List<Map<String, dynamic>> friendList = [];
      for (var f in friendshipsRes) {
        final friendId = f['user_id'] == user.id ? f['friend_id'] : f['user_id'];
        final profile = await supabase
            .from('profiles')
            .select('id, username, level')
            .eq('id', friendId)
            .single();
        friendList.add(profile);
      }

      if (mounted) {
        setState(() {
          _friends = friendList;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading party data: $e');
    }
  }

  void _listenToPartyLobby(String partyId) {
    _lobbyChannel?.unsubscribe();
    _lobbyChannel = supabase.channel('party_lobby_$partyId')
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'parties',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: partyId),
        callback: (payload) {
          final newStatus = payload.newRecord['status'];
          if (newStatus == 'in_match') {
            _launchIntoGame();
          }
        },
      )
      .subscribe();
  }

  void _launchIntoGame() {
    if (_currentParty == null) return;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final bool isGunner = _currentParty!['leader_id'] != user.id;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          body: GameWidget<GraveStakesGame>(
            game: GraveStakesGame(
              roomId: _currentParty!['id'], 
              isGunner: isGunner,
            ),
            // ADDED: Loading builder prevents black screen during ZIP extraction
            loadingBuilder: (context) => Container(
              color: Colors.black,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.purpleAccent),
                    SizedBox(height: 20),
                    Text(
                      'DEPLOYING SQUAD...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2.0,
                        fontFamily: 'Courier',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // ADDED: Overlay map prevents the red-screen crash!
            overlayBuilderMap: {
              'summary': (BuildContext context, GraveStakesGame game) => MatchSummaryOverlay(game: game),
              'searching': (BuildContext context, GraveStakesGame game) => SearchingOverlay(game: game),
              'countdown': (BuildContext context, GraveStakesGame game) => CountdownOverlay(game: game),
            },
          ),
        ),
      ),
    ).then((_) async {
      if (!isGunner) {
        await supabase.from('parties').update({'status': 'formed'}).eq('id', _currentParty!['id']);
      }
      _loadPartyAndFriends();
    });
  }

  Future<void> _createParty() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final partyRes = await supabase.from('parties').insert({
        'leader_id': user.id,
        'status': 'formed',
      }).select().single();

      await supabase.from('party_members').insert({
        'party_id': partyRes['id'],
        'user_id': user.id,
        'status': 'accepted',
      });

      _loadPartyAndFriends();
    } catch (e) {
      debugPrint('Error creating party: $e');
    }
  }

  Future<void> _inviteFriend(String friendId) async {
    if (_currentParty == null) return;
    try {
      await supabase.from('party_members').insert({
        'party_id': _currentParty!['id'],
        'user_id': friendId,
        'status': 'accepted',
      });
      _loadPartyAndFriends();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Friend added to squad!'), backgroundColor: Colors.green));
      }
    } catch (e) {
      debugPrint('Error inviting friend: $e');
    }
  }

  Future<void> _leaveParty() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      await supabase.from('party_members').delete().eq('user_id', user.id);
      
      if (_currentParty != null && _currentParty!['leader_id'] == user.id) {
        await supabase.from('parties').delete().eq('id', _currentParty!['id']);
      }

      setState(() {
        _currentParty = null;
        _partyMembers = [];
      });
      _loadPartyAndFriends();
    } catch (e) {
      debugPrint('Error leaving party: $e');
    }
  }

  Future<void> _startPartyMatch() async {
    if (_currentParty == null) return;
    try {
      await supabase.from('parties').update({'status': 'in_match'}).eq('id', _currentParty!['id']);
    } catch (e) {
      debugPrint('Error starting match: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;
    final isLeader = _currentParty != null && user != null && _currentParty!['leader_id'] == user.id;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        title: const Text('SQUAD PARTY', style: TextStyle(color: Colors.redAccent, letterSpacing: 1.5, fontFamily: 'Courier')),
        actions: [
          if (_currentParty != null)
            IconButton(
              icon: const Icon(Icons.exit_to_app, color: Colors.redAccent),
              onPressed: _leaveParty,
              tooltip: 'Disband / Leave Squad',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.red))
          : _currentParty == null
              ? Center(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[800],
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _createParty,
                    child: const Text('CREATE SQUAD PARTY', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('SQUAD MEMBERS', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'Courier')),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 140,
                        child: ListView.builder(
                          itemCount: _partyMembers.length,
                          itemBuilder: (context, index) {
                            final member = _partyMembers[index];
                            final profile = member['profiles'] ?? {};
                            final isThisUserLeader = member['user_id'] == _currentParty!['leader_id'];
                            
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey[900], 
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: isThisUserLeader ? Colors.amber.withOpacity(0.5) : Colors.greenAccent.withOpacity(0.3)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${profile['username'] ?? 'Ghost'} (Lv. ${profile['level'] ?? 1})', 
                                    style: const TextStyle(color: Colors.white, fontSize: 16, fontFamily: 'Courier')
                                  ),
                                  Icon(
                                    isThisUserLeader ? Icons.directions_car : Icons.track_changes, 
                                    color: isThisUserLeader ? Colors.amber : Colors.greenAccent, 
                                    size: 20
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const Divider(height: 40, color: Colors.grey),
                      const Text('INVITE ALLIES', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'Courier')),
                      const SizedBox(height: 12),
                      Expanded(
                        child: _friends.isEmpty
                            ? const Center(child: Text('No allies online.', style: TextStyle(color: Colors.grey)))
                            : ListView.builder(
                                itemCount: _friends.length,
                                itemBuilder: (context, index) {
                                  final friend = _friends[index];
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(color: Colors.grey[950], borderRadius: BorderRadius.circular(8)),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('${friend['username']} (Lv. ${friend['level']})', style: const TextStyle(color: Colors.white, fontFamily: 'Courier')),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red[800]),
                                          onPressed: () => _inviteFriend(friend['id']),
                                          child: const Text('INVITE', style: TextStyle(color: Colors.white)),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                      if (isLeader) ...[
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red[800],
                              padding: const EdgeInsets.symmetric(vertical: 18),
                            ),
                            onPressed: _startPartyMatch,
                            child: const Text('DEPLOY SQUAD', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5, fontFamily: 'Courier')),
                          ),
                        ),
                      ],
                      if (!isLeader) ...[
                        const SizedBox(height: 16),
                        const Center(
                          child: Text('Awaiting orders from Squad Leader...', style: TextStyle(color: Colors.amber, fontStyle: FontStyle.italic, fontFamily: 'Courier')),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }
}

// ==========================================
// OVERLAYS
// ==========================================
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
            const Text(
              'SEARCHING PUBLIC MATCHMAKING...',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2, fontFamily: 'Courier'),
            ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.redAccent),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: () => Navigator.of(context).pop(), // Kills the Flame engine and routes back to Party Screen
              icon: const Icon(Icons.close, color: Colors.redAccent),
              label: const Text('ABORT DEPLOYMENT', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
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
            fontFamily: 'Courier',
            shadows: [Shadow(color: Colors.black, blurRadius: 10)]
          ),
        ),
      ),
    );
  }
}