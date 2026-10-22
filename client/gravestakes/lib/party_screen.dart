// party_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flame/game.dart';
import 'game.dart';
import 'match_summary_overlay.dart'; 

class PartyScreen extends StatefulWidget {
  const PartyScreen({super.key});

  @override
  State<PartyScreen> createState() => _PartyScreenState();
}

class _PartyScreenState extends State<PartyScreen> {
  final supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isLaunchingMatch = false; // Prevents double-pushing into the same match
  Map<String, dynamic>? _currentParty;
  List<Map<String, dynamic>> _partyMembers = [];
  List<Map<String, dynamic>> _friends = [];
  int _myLevel = 1;
  
  RealtimeChannel? _lobbyChannel;

  String _selectedMatchMode = '2v2';
  bool _isJuggernautMode = false;

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
      final myProfile = await supabase
          .from('profiles')
          .select('level')
          .eq('id', user.id)
          .maybeSingle();
      if (myProfile != null) {
        _myLevel = (myProfile['level'] as num?)?.toInt() ?? 1;
      }

      final membership = await supabase
          .from('party_members')
          .select('party_id, parties(*)')
          .eq('user_id', user.id)
          .maybeSingle();

      if (membership != null && membership['parties'] != null) {
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

      final Set<String> friendIds = {};
      for (var f in friendshipsRes) {
        final String fId = f['user_id'] == user.id ? f['friend_id'] : f['user_id'];
        friendIds.add(fId);
      }

      // FIXED: Single batch query for all friends instead of N+1 sequential queries
      List<Map<String, dynamic>> friendList = [];
      if (friendIds.isNotEmpty) {
        final profilesRes = await supabase
            .from('profiles')
            .select('id, username, level')
            .inFilter('id', friendIds.toList());
        friendList = List<Map<String, dynamic>>.from(profilesRes);
      }

      if (mounted) {
        setState(() {
          _friends = friendList;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading party data: $e');
      if (mounted) setState(() => _isLoading = false);
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
          if (newStatus == 'in_match' && !_isLaunchingMatch) {
            final matchId = payload.newRecord['match_id'] as String?;
            final mode = payload.newRecord['match_mode'] as String? ?? 'casual';
            final isJuggernaut = payload.newRecord['is_juggernaut'] as bool? ?? false;
            
            if (matchId != null) {
              _launchIntoGame(matchId, mode, isJuggernaut);
            }
          } else if (newStatus == 'formed') {
            _loadPartyAndFriends();
          }
        },
      )
      // FIXED: Also listen to party_members changes so the roster updates live when friends join/leave!
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'party_members',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'party_id', value: partyId),
        callback: (payload) {
          _loadPartyAndFriends();
        },
      )
      .subscribe();
  }

  Future<void> _launchIntoGame(String roomId, String matchMode, bool isJuggernaut) async {
    if (_currentParty == null || _isLaunchingMatch) return;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    String? partnerUserId;
    for (final m in _partyMembers) {
      if (m['user_id'] != user.id) {
        partnerUserId = m['user_id'].toString();
        break;
      }
    }

    _isLaunchingMatch = true;
    final String leaderId = _currentParty!['leader_id'];
    
    // You are ONLY a Gunner if Juggernaut is enabled AND you are not the Party Leader
    final bool isGunner = isJuggernaut && (leaderId != user.id);
    final bool hasGunner = isJuggernaut && (_partyMembers.length > 1);

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          body: GameWidget<GraveStakesGame>(
            game: GraveStakesGame(
              roomId: roomId, 
              matchMode: matchMode,
              isGunner: isGunner,
              hasGunner: hasGunner,
              driverId: isJuggernaut ? leaderId : null,
              partyPartnerUserId: partnerUserId, // <-- Keeps 2v2 Party Partners on Team 1!
            ),
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
            overlayBuilderMap: {
              'summary': (BuildContext context, GraveStakesGame game) => MatchSummaryOverlay(game: game),
              'searching': (BuildContext context, GraveStakesGame game) => SearchingOverlay(game: game),
              'countdown': (BuildContext context, GraveStakesGame game) => CountdownOverlay(game: game),
            },
          ),
        ),
      ),
    );

    _isLaunchingMatch = false;

    if (user.id == leaderId && _currentParty != null) {
      try {
        await supabase.from('parties').update({'status': 'formed'}).eq('id', _currentParty!['id']);
      } catch (_) {}
    }
    if (mounted) {
      _loadPartyAndFriends();
    }
  }

  Future<void> _createParty() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);
    try {
      // Clean up any stale party memberships first
      await supabase.from('party_members').delete().eq('user_id', user.id);

      final partyRes = await supabase.from('parties').insert({
        'leader_id': user.id,
        'status': 'formed',
      }).select().single();

      await supabase.from('party_members').insert({
        'party_id': partyRes['id'],
        'user_id': user.id,
        'status': 'accepted',
      });

      await _loadPartyAndFriends();
    } catch (e) {
      debugPrint('Error creating party: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _inviteFriend(String friendId) async {
    if (_currentParty == null) return;
    if (_partyMembers.any((m) => m['user_id'] == friendId)) return;

    try {
      await supabase.from('party_members').insert({
        'party_id': _currentParty!['id'],
        'user_id': friendId,
        'status': 'accepted',
      });
      await _loadPartyAndFriends();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Friend added to squad!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint('Error inviting friend: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Friend is already in another squad!'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _leaveParty() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    _lobbyChannel?.unsubscribe();
    try {
      if (_currentParty != null && _currentParty!['leader_id'] == user.id) {
        await supabase.from('party_members').delete().eq('party_id', _currentParty!['id']);
        await supabase.from('parties').delete().eq('id', _currentParty!['id']);
      } else {
        await supabase.from('party_members').delete().eq('user_id', user.id);
      }

      if (mounted) {
        setState(() {
          _currentParty = null;
          _partyMembers = [];
        });
      }
      await _loadPartyAndFriends();
    } catch (e) {
      debugPrint('Error leaving party: $e');
    }
  }

  Future<void> _startPartyMatch() async {
    if (_currentParty == null || _isLaunchingMatch) return;
    setState(() => _isLoading = true);

    try {
      int targetPlayers = 8;
      if (_selectedMatchMode == '1v1') targetPlayers = 2;
      if (_selectedMatchMode == '2v2') targetPlayers = 4;

      final user = supabase.auth.currentUser;
      
      final memberRes = await supabase.from('guild_members').select('guild_id').eq('user_id', user!.id).maybeSingle();
      final guildId = memberRes?['guild_id'];

      // FIXED: Include p_player_level so it routes to the exact same RPC overload as MainMenuScreen!
      final matchId = await supabase.rpc(
        'find_or_create_match',
        params: {
          'p_map_name': 'L1T1V1.0.0',
          'p_mode': _selectedMatchMode,
          'p_target_players': targetPlayers,
          'p_guild_id': guildId,
          'p_player_level': _myLevel,
        }, 
      );

      await supabase.from('parties').update({
        'status': 'in_match',
        'match_id': matchId.toString(),
        'match_mode': _selectedMatchMode,
        'is_juggernaut': _isJuggernautMode,
      }).eq('id', _currentParty!['id']);

      // Fallback launch in case Realtime PostgresChanges is delayed
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted && !_isLaunchingMatch) {
          _launchIntoGame(matchId.toString(), _selectedMatchMode, _isJuggernautMode);
        }
      });
    } catch (e) {
      debugPrint('Error starting squad match: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;
    final isLeader = _currentParty != null && user != null && _currentParty!['leader_id'] == user.id;
    final Set<String> memberIds = _partyMembers.map((m) => m['user_id'].toString()).toSet();

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
                            ? const Center(child: Text('No allies found.', style: TextStyle(color: Colors.grey)))
                            : ListView.builder(
                                itemCount: _friends.length,
                                itemBuilder: (context, index) {
                                  final friend = _friends[index];
                                  final bool isAlreadyInParty = memberIds.contains(friend['id'].toString());
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(color: Colors.grey[950], borderRadius: BorderRadius.circular(8)),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('${friend['username']} (Lv. ${friend['level']})', style: const TextStyle(color: Colors.white, fontFamily: 'Courier')),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: isAlreadyInParty ? Colors.grey[800] : Colors.red[800],
                                          ),
                                          onPressed: isAlreadyInParty ? null : () => _inviteFriend(friend['id']),
                                          child: Text(isAlreadyInParty ? 'IN SQUAD' : 'INVITE', style: const TextStyle(color: Colors.white)),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),

                      if (isLeader) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.grey[900],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.purpleAccent.withOpacity(0.5)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedMatchMode,
                              dropdownColor: Colors.black,
                              isExpanded: true,
                              style: const TextStyle(color: Colors.purpleAccent, fontFamily: 'Courier', fontWeight: FontWeight.bold),
                              items: const [
                                DropdownMenuItem(value: 'casual', child: Text('CASUAL FFA (8 PLAYERS)')),
                                DropdownMenuItem(value: '1v1', child: Text('1v1 RANKED (2 PLAYERS)')),
                                DropdownMenuItem(value: '2v2', child: Text('2v2 SQUAD (4 PLAYERS)')),
                              ],
                              onChanged: (String? newValue) {
                                if (newValue != null) {
                                  setState(() {
                                    _selectedMatchMode = newValue;
                                    if (newValue == '1v1') _isJuggernautMode = false;
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          title: const Text('FORM JUGGERNAUT DUO', style: TextStyle(color: Colors.white, fontFamily: 'Courier', fontWeight: FontWeight.bold)),
                          subtitle: const Text('Leader drives. Partner covers the rear.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          activeColor: Colors.amberAccent,
                          value: _isJuggernautMode,
                          onChanged: (_selectedMatchMode == '1v1' || _partyMembers.length < 2) ? null : (bool value) {
                            setState(() => _isJuggernautMode = value);
                          },
                        ),
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
              onPressed: () => Navigator.of(context).pop(), 
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