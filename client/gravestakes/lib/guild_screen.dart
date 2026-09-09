import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flame/game.dart';
import 'game.dart';
import 'spectator_mode.dart';
import 'match_summary_overlay.dart';

class GuildScreen extends StatefulWidget {
  const GuildScreen({super.key});

  @override
  State<GuildScreen> createState() => _GuildScreenState();
}

class _GuildScreenState extends State<GuildScreen> {
  final supabase = Supabase.instance.client;
  
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _tagController = TextEditingController();
  final TextEditingController _chatController = TextEditingController();

  bool _isLoading = true;
  Map<String, dynamic>? _myGuild;
  String _myRole = 'member';
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _publicGuilds = [];
  List<Map<String, dynamic>> _messages = [];
  RealtimeChannel? _chatChannel;

  @override
  void initState() {
    super.initState();
    _loadGuildData();
  }

  @override
  void dispose() {
    _chatChannel?.unsubscribe();
    _nameController.dispose();
    _tagController.dispose();
    _chatController.dispose();
    super.dispose();
  }

  Future<void> _loadGuildData() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final membership = await supabase
          .from('guild_members')
          .select('guild_id, role, guilds(*)')
          .eq('user_id', user.id)
          .maybeSingle();

      if (membership != null) {
        _myGuild = membership['guilds'];
        final guildId = _myGuild!['id'];
        
        if (_myGuild!['founder_id'] == user.id && membership['role'] != 'founder') {
          await supabase.from('guild_members')
              .update({'role': 'founder'})
              .eq('guild_id', guildId)
              .eq('user_id', user.id);
          _myRole = 'founder';
        } else {
          _myRole = membership['role'];
        }

        final membersRes = await supabase
            .from('guild_members')
            .select('user_id, role, profiles(username, level)')
            .eq('guild_id', guildId);

        await _fetchMessages(guildId);

        if (mounted) {
          setState(() {
            _members = List<Map<String, dynamic>>.from(membersRes);
            _isLoading = false;
          });
        }

        _subscribeToChat(guildId);
      } else {
        final publicRes = await supabase.from('guilds').select('*');
        if (mounted) {
          setState(() {
            _publicGuilds = List<Map<String, dynamic>>.from(publicRes);
            _myGuild = null;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading guild data: $e');
    }
  }

  Future<void> _fetchMessages(String guildId) async {
    // UPDATED: Now selects the new 'metadata' column
    final messagesRes = await supabase
        .from('guild_messages')
        .select('id, message, sender_id, created_at, metadata, profiles(username)')
        .eq('guild_id', guildId)
        .order('created_at', ascending: true)
        .limit(50);

    if (mounted) {
      setState(() {
        _messages = List<Map<String, dynamic>>.from(messagesRes);
      });
    }
  }

  void _subscribeToChat(String guildId) {
    _chatChannel?.unsubscribe();
    
    _chatChannel = supabase.channel('guild_chat_$guildId')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'guild_messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'guild_id',
          value: guildId,
        ),
        callback: (payload) {
          _fetchMessages(guildId);
        },
      )
      .subscribe();
  }

  String _bleepText(String text) {
    final badWords = ['badword1', 'toxicword', 'rudeword'];
    String cleaned = text;
    for (var word in badWords) {
      cleaned = cleaned.replaceAll(RegExp(word, caseSensitive: false), '***');
    }
    return cleaned;
  }

  Future<void> _createGuild() async {
    final name = _nameController.text.trim();
    final tag = _tagController.text.trim().toUpperCase();
    if (name.isEmpty || tag.isEmpty) return;

    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final guildRes = await supabase.from('guilds').insert({
        'name': name,
        'tag': tag,
        'founder_id': user.id,
      }).select().single();

      await supabase.from('guild_members').insert({
        'guild_id': guildRes['id'],
        'user_id': user.id,
        'role': 'founder',
      });

      _nameController.clear();
      _tagController.clear();
      setState(() => _isLoading = true);
      _loadGuildData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating guild: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _joinGuild(String guildId) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final guildInfo = await supabase.from('guilds').select('founder_id').eq('id', guildId).single();
      final bool isFounder = guildInfo['founder_id'] == user.id;

      await supabase.from('guild_members').insert({
        'guild_id': guildId,
        'user_id': user.id,
        'role': isFounder ? 'founder' : 'member',
      });

      setState(() => _isLoading = true);
      _loadGuildData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to join guild: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _promptLeaveOrDisband() async {
    final user = supabase.auth.currentUser;
    if (user == null || _myGuild == null) return;

    final bool isFounder = _myGuild!['founder_id'] == user.id;
    final otherMembers = _members.where((m) => m['user_id'] != user.id).toList();

    if (!isFounder) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text('Leave Guild?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: const Text('Are you sure you want to leave this guild?', style: TextStyle(color: Colors.grey)),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('CANCEL', style: TextStyle(color: Colors.grey))),
            TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('LEAVE', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
          ],
        ),
      );

      if (confirmed == true) {
        try {
          _chatChannel?.unsubscribe();
          await supabase.from('guild_members').delete().eq('user_id', user.id);
          setState(() { _myGuild = null; _isLoading = true; });
          _loadGuildData();
        } catch (e) { debugPrint('Error leaving guild: $e'); }
      }
    } else if (otherMembers.isEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text('Disband Guild?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: const Text('You are the last member in this guild. Leaving will permanently disband it.', style: TextStyle(color: Colors.grey)),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('CANCEL', style: TextStyle(color: Colors.grey))),
            TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('DISBAND', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
          ],
        ),
      );

      if (confirmed == true) {
        try {
          _chatChannel?.unsubscribe();
          await supabase.from('guilds').delete().eq('id', _myGuild!['id']);
          setState(() { _myGuild = null; _isLoading = true; });
          _loadGuildData();
        } catch (e) { debugPrint('Error disbanding guild: $e'); }
      }
    } else {
      String? selectedSuccessorId = otherMembers.first['user_id'];
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setStateDialog) {
              return AlertDialog(
                backgroundColor: Colors.grey[900],
                title: const Text('Appoint Successor', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('You must appoint a new leader before leaving.', style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      dropdownColor: Colors.grey[850],
                      value: selectedSuccessorId,
                      items: otherMembers.map((m) {
                        return DropdownMenuItem<String>(
                          value: m['user_id'] as String,
                          child: Text(m['profiles']?['username'] ?? 'Ghost', style: const TextStyle(color: Colors.white)),
                        );
                      }).toList(),
                      onChanged: (val) { setStateDialog(() { selectedSuccessorId = val; }); },
                    ),
                  ],
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('CANCEL', style: TextStyle(color: Colors.grey))),
                  TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('PROMOTE & LEAVE', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
                ],
              );
            },
          );
        },
      );

      if (confirmed == true && selectedSuccessorId != null) {
        try {
          _chatChannel?.unsubscribe();
          await supabase.from('guild_members').update({'role': 'founder'}).eq('guild_id', _myGuild!['id']).eq('user_id', selectedSuccessorId!);
          await supabase.from('guilds').update({'founder_id': selectedSuccessorId}).eq('id', _myGuild!['id']);
          await supabase.from('guild_members').delete().eq('user_id', user.id);
          setState(() { _myGuild = null; _isLoading = true; });
          _loadGuildData();
        } catch (e) { debugPrint('Error transferring leadership: $e'); }
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty || _myGuild == null) return;

    final user = supabase.auth.currentUser;
    if (user == null) return;

    final moderatedText = _bleepText(text);
    _chatController.clear();

    try {
      await supabase.from('guild_messages').insert({
        'guild_id': _myGuild!['id'],
        'sender_id': user.id,
        'message': moderatedText,
        'metadata': {},
      });
      await _fetchMessages(_myGuild!['id']);
    } catch (e) {
      debugPrint('Error sending message: $e');
    }
  }

  Future<void> _sendScrimmageInvite(String mode) async {
    final user = supabase.auth.currentUser;
    if (user == null || _myGuild == null) return;

    final String customRoomId = 'scrimmage_${DateTime.now().millisecondsSinceEpoch}_${user.id.substring(0, 5)}';
    final int targetPlayers = mode == '1v1' ? 2 : 4;

    final metadata = {
      'type': 'scrimmage_invite',
      'room_id': customRoomId,
      'mode': mode, 
      'status': 'waiting',
      'players': [user.id], 
      'results': {},
    };

    try {
      final response = await supabase.from('guild_messages').insert({
        'guild_id': _myGuild!['id'],
        'sender_id': user.id,
        'message': 'issued a $mode sparring challenge!',
        'metadata': metadata,
      }).select('id').single();

      await _fetchMessages(_myGuild!['id']);
      
      _launchScrimmage(
        roomId: customRoomId, 
        mode: mode, 
        targetPlayers: targetPlayers, 
        messageId: response['id'].toString(), 
      );
      
    } catch (e) {
      debugPrint('Error sending scrimmage invite: $e');
    }
  }

  Future<void> _joinScrimmage(String messageId, Map<String, dynamic> metadata) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final String mode = metadata['mode'];
    final int targetPlayers = mode == '1v1' ? 2 : 4;
    final String customRoomId = metadata['room_id'];
    List<String> players = List<String>.from(metadata['players'] ?? []);

    if (!players.contains(user.id)) {
      players.add(user.id);
      
      String newStatus = players.length >= targetPlayers ? 'playing' : 'waiting';
      Map<String, dynamic> newMetadata = Map.from(metadata);
      newMetadata['players'] = players;
      newMetadata['status'] = newStatus;

      await supabase.from('guild_messages').update({
        'metadata': newMetadata
      }).eq('id', messageId);
    }

    _launchScrimmage(
      roomId: customRoomId, 
      mode: mode, 
      targetPlayers: targetPlayers, 
      messageId: messageId, 
    );
  }

  Future<void> _cancelScrimmage(String messageId, Map<String, dynamic> metadata) async {
    Map<String, dynamic> newMetadata = Map.from(metadata);
    newMetadata['status'] = 'cancelled';

    // 1. Optimistic local update (makes the UI feel instantly responsive)
    setState(() {
      final index = _messages.indexWhere((m) => m['id'].toString() == messageId);
      if (index != -1) {
        _messages[index]['metadata'] = newMetadata;
      }
    });

    try {
      // 2. Fire the database update
      await supabase.from('guild_messages').update({
        'metadata': newMetadata
      }).eq('id', messageId);
      
    } catch (e) {
      // 3. Surface the error so we aren't flying blind
      debugPrint('Error cancelling scrimmage: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to cancel (RLS issue?): $e'), backgroundColor: Colors.red),
        );
      }
      // Revert the optimistic update if it failed
      _fetchMessages(_myGuild!['id']); 
    }
  }

  void _launchScrimmage({required String roomId, required String mode, required int targetPlayers, required String messageId}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          body: GameWidget<GraveStakesGame>(
            game: GraveStakesGame(
              roomId: roomId,
              matchMode: mode,
              targetPlayers: targetPlayers,
              isGuildScrimmage: true,
              scrimmageMessageId: messageId,
            ),
            // THE FIX: Add the loadingBuilder to show UI during asset extraction
            loadingBuilder: (context) => Container(
              color: Colors.black,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.purpleAccent),
                    SizedBox(height: 20),
                    Text(
                      'PREPARING MATCH...',
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
    ).then((_) {
      _fetchMessages(_myGuild!['id']);
    });
  }

  void _spectateScrimmage(String roomId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          body: Stack(
            children: [
              GameWidget<SpectatorGame>(
                game: SpectatorGame(roomId: roomId, mapName: 'L1T1V1.0.0'),
                overlayBuilderMap: {
                  'spectator_summary': (context, SpectatorGame game) => SpectatorSummaryOverlay(game: game),
                },
              ),
              Positioned(
                top: 40,
                left: 20,
                child: Container(
                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white, size: 30),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showChallengeMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('ISSUE CHALLENGE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            const Divider(color: Colors.grey),
            ListTile(
              leading: const Icon(Icons.person, color: Colors.orangeAccent),
              title: const Text('1v1 Sparring Match', style: TextStyle(color: Colors.white)),
              subtitle: const Text('No cost, no loot. Just glory.', style: TextStyle(color: Colors.white54, fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _sendScrimmageInvite('1v1');
              },
            ),
            ListTile(
              leading: const Icon(Icons.people, color: Colors.orangeAccent),
              title: const Text('2v2 Squad Scrimmage', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Team training session.', style: TextStyle(color: Colors.white54, fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _sendScrimmageInvite('2v2');
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showTreasuryModal(BuildContext context) {
    final user = supabase.auth.currentUser;
    final bool isFounder = _myGuild != null && user != null && _myGuild!['founder_id'] == user.id;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateModal) {
          int currentDividend = _myGuild?['dividend_rate'] ?? 20;
          String currentDoctrine = _myGuild?['active_doctrine'] ?? 'none';
          String currentStrike = _myGuild?['active_strike'] ?? 'none';
          int vaultCoins = _myGuild?['vault_coins'] ?? 0;
          int vaultShadows = _myGuild?['vault_shadows'] ?? 0;

          Future<void> updateGuildField(String field, dynamic value) async {
            try {
              await supabase.from('guilds').update({field: value}).eq('id', _myGuild!['id']);
              setState(() {
                _myGuild![field] = value;
              });
              setStateModal(() {});
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Vault configuration updated!'), backgroundColor: Colors.green),
                );
              }
            } catch (e) {
              debugPrint('Error updating vault: $e');
            }
          }

          return Container(
            padding: const EdgeInsets.all(20),
            height: MediaQuery.of(context).size.height * 0.8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('GUILD TREASURY & DOCTRINES', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'Courier')),
                    IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                const Divider(color: Colors.white24),
                Expanded(
                  child: ListView(
                    children: [
                      // SECTION 1: DIVIDEND SLIDER
                      const Text('WEEKLY SUNDAY DIVIDEND SPLIT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'Courier')),
                      const SizedBox(height: 4),
                      Text('Percentage of Vault Coins paid out to members weekly: $currentDividend%', style: const TextStyle(color: Colors.grey, fontSize: 11, fontFamily: 'Courier')),
                      Slider(
                        value: currentDividend.toDouble(),
                        min: 0,
                        max: 100,
                        divisions: 10,
                        activeColor: Colors.amberAccent,
                        inactiveColor: Colors.grey[800],
                        onChanged: isFounder ? (val) {
                          setStateModal(() {
                            _myGuild!['dividend_rate'] = val.toInt();
                          });
                        } : null,
                        onChangeEnd: isFounder ? (val) {
                          updateGuildField('dividend_rate', val.toInt());
                        } : null,
                      ),
                      const Divider(height: 30, color: Colors.white24),

                      // SECTION 2: PERMANENT PASSIVES (GUILD DOCTRINES)
const Text('GUILD DOCTRINE (SPECIES FOCUS)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'Courier')),
const SizedBox(height: 4),
const Text('Buffs squad defense & scare power against specific target types.', style: TextStyle(color: Colors.grey, fontSize: 11, fontFamily: 'Courier')),
const SizedBox(height: 12),

_buildDoctrineCard(
  title: 'Xenophobic Protocol',
  desc: '+10% Scare Stun against ALIEN species.',
  id: 'alien',
  current: currentDoctrine,
  isFounder: isFounder,
  onSelect: () => updateGuildField('active_doctrine', 'alien'),
),
_buildDoctrineCard(
  title: 'Bestial Ward',
  desc: '+10% Scare Stun against BEAST species.',
  id: 'beast',
  current: currentDoctrine,
  isFounder: isFounder,
  onSelect: () => updateGuildField('active_doctrine', 'beast'),
),
_buildDoctrineCard(
  title: 'Anti-Tech Protocol',
  desc: '+10% Scare Stun against CYBERNETIC species.',
  id: 'cybernetic',
  current: currentDoctrine,
  isFounder: isFounder,
  onSelect: () => updateGuildField('active_doctrine', 'cybernetic'),
),
_buildDoctrineCard(
  title: 'Phantom Bane',
  desc: '+10% Scare Stun against GHOST species.',
  id: 'ghost',
  current: currentDoctrine,
  isFounder: isFounder,
  onSelect: () => updateGuildField('active_doctrine', 'ghost'),
),
_buildDoctrineCard(
  title: 'Bio-Defense Pact',
  desc: '+10% Scare Stun against HUMANOID species.',
  id: 'humanoid',
  current: currentDoctrine,
  isFounder: isFounder,
  onSelect: () => updateGuildField('active_doctrine', 'humanoid'),
),
                      const Divider(height: 30, color: Colors.white24),

                      // SECTION 3: TACTICAL STRIKES (PRIME-TIME CONSUMABLES)
                      const Text('PRIME-TIME TACTICAL STRIKES', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'Courier')),
                      const SizedBox(height: 4),
                      const Text('One-time consumables purchased with Vault Shadows for Crypt War advantage.', style: TextStyle(color: Colors.grey, fontSize: 11, fontFamily: 'Courier')),
                      const SizedBox(height: 12),

                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.purpleAccent.withOpacity(0.4))),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('The Scrambler', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
                                Text('Blinds node progress tracking for rivals (Cost: 500 Shadows)', style: TextStyle(color: Colors.grey, fontSize: 10, fontFamily: 'Courier')),
                              ],
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.purple[800]),
                              onPressed: isFounder && vaultShadows >= 500 ? () {
                                // Deduct shadows & activate strike logic here
                                updateGuildField('active_strike', 'scrambler');
                              } : null,
                              child: const Text('DEPLOY', style: TextStyle(color: Colors.white, fontFamily: 'Courier', fontSize: 11)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDoctrineCard({required String title, required String desc, required String id, required String current, required bool isFounder, required VoidCallback onSelect}) {
    bool isSelected = current == id;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSelected ? Colors.red[900]?.withOpacity(0.3) : Colors.black45,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isSelected ? Colors.redAccent : Colors.white24),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'Courier')),
                const SizedBox(height: 2),
                Text(desc, style: const TextStyle(color: Colors.grey, fontSize: 11, fontFamily: 'Courier')),
              ],
            ),
          ),
          if (isFounder)
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: isSelected ? Colors.grey[800] : Colors.red[800]),
              onPressed: isSelected ? null : onSelect,
              child: Text(isSelected ? 'ACTIVE' : 'SELECT', style: const TextStyle(color: Colors.white, fontSize: 10, fontFamily: 'Courier')),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;
    final bool isFounder = _myGuild != null && user != null && _myGuild!['founder_id'] == user.id;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        title: Text(
          _myGuild != null ? '${_myGuild!['name']} [${_myGuild!['tag']}]' : 'GUILDS',
          style: const TextStyle(color: Colors.redAccent, letterSpacing: 1.5),
        ),
        actions: [
          if (_myGuild != null)
            IconButton(
              icon: Icon(isFounder ? Icons.delete_forever : Icons.exit_to_app, color: Colors.redAccent),
              onPressed: _promptLeaveOrDisband,
              tooltip: isFounder ? 'Disband / Leave Guild' : 'Leave Guild',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.red))
          : _myGuild == null
              ? _buildGuildBrowser()
              : _buildGuildDashboard(),
    );
  }

  Widget _buildGuildBrowser() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('CREATE A GUILD', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Guild Name',
              hintStyle: const TextStyle(color: Colors.grey),
              filled: true,
              fillColor: Colors.grey[900],
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _tagController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Tag (e.g. GHOST)',
              hintStyle: const TextStyle(color: Colors.grey),
              filled: true,
              fillColor: Colors.grey[900],
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[800]),
            onPressed: _createGuild,
            child: const Text('CREATE GUILD', style: TextStyle(color: Colors.white)),
          ),
          const Divider(height: 40, color: Colors.grey),
          const Text('PUBLIC GUILDS', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          Expanded(
            child: _publicGuilds.isEmpty
                ? const Center(child: Text('No guilds found. Create your own!', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: _publicGuilds.length,
                    itemBuilder: (context, index) {
                      final guild = _publicGuilds[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('${guild['name']} [${guild['tag']}]', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red[800]),
                              onPressed: () => _joinGuild(guild['id']),
                              child: const Text('JOIN', style: TextStyle(color: Colors.white)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildScrimmageBubble(Map<String, dynamic> msg, Map<String, dynamic> metadata) {
    final profile = msg['profiles'] ?? {};
    final senderName = profile['username'] ?? 'Ghost';
    final status = metadata['status'] as String? ?? 'waiting';
    final mode = metadata['mode'] as String? ?? '1v1';
    final roomId = metadata['room_id'] as String;
    final targetPlayers = mode == '1v1' ? 2 : 4;
    final players = List<String>.from(metadata['players'] ?? []);
    final results = metadata['results'] as Map<String, dynamic>? ?? {};

    final myId = supabase.auth.currentUser?.id;
    final alreadyJoined = myId != null && players.contains(myId);
    final isHost = msg['sender_id'] == myId; // Check if I created the invite

    return Container(
      margin: const EdgeInsets.only(bottom: 12.0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        border: Border.all(
          color: status == 'cancelled' ? Colors.grey.withOpacity(0.5) : Colors.orangeAccent.withOpacity(0.5)
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sports_martial_arts, color: status == 'cancelled' ? Colors.grey : Colors.orangeAccent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$senderName issued a $mode Sparring Challenge!', 
                  style: TextStyle(color: status == 'cancelled' ? Colors.grey : Colors.white, fontWeight: FontWeight.bold)
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          if (status == 'waiting') ...[
            Text('Waiting for fighters (${players.length}/$targetPlayers)...', style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 8),
            
            if (alreadyJoined)
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[700]),
                      onPressed: () => _joinScrimmage(msg['id'].toString(), metadata),
                      child: const Text('RETURN', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  if (isHost) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.redAccent)),
                        onPressed: () => _cancelScrimmage(msg['id'].toString(), metadata),
                        child: const Text('CANCEL', style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800]),
                  onPressed: () => _joinScrimmage(msg['id'].toString(), metadata),
                  child: const Text('JOIN MATCH', style: TextStyle(color: Colors.white)),
                ),
              ),
          ] else if (status == 'playing') ...[
            const Text('Match in progress...', style: TextStyle(color: Colors.amber)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.amber)),
                onPressed: () => _spectateScrimmage(roomId),
                icon: const Icon(Icons.remove_red_eye, color: Colors.amber),
                label: const Text('SPECTATE', style: TextStyle(color: Colors.amber)),
              ),
            ),
          ] else if (status == 'finished') ...[
            const Text('Match Concluded', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            ...results.entries.map((e) => Text('${e.key}: ${e.value} Souls', style: const TextStyle(color: Colors.white70))),
          ] else if (status == 'cancelled') ...[
            const Text('Challenge Withdrawn', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
          ]
        ],
      ),
    );
  }

  Widget _buildGuildDashboard() {
    final user = supabase.auth.currentUser;
    final bool isFounder = _myGuild != null && user != null && _myGuild!['founder_id'] == user.id;
    
    final vaultCoins = _myGuild?['vault_coins'] ?? 0;
    final vaultShadows = _myGuild?['vault_shadows'] ?? 0;
    final guildLevel = _myGuild?['guild_level'] ?? 1;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.grey[900],
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Text('Level $guildLevel Guild', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
              Text('Vault Shadows: $vaultShadows', style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Courier')),
              Text('Vault Coins: $vaultCoins', style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontFamily: 'Courier')),
            ],
          ),
        ),
        const Divider(height: 1, color: Colors.white24),

        Container(
          height: 120,
          padding: const EdgeInsets.all(8),
          color: Colors.grey[950],
          child: ListView.builder(
            itemCount: _members.length,
            itemBuilder: (context, index) {
              final member = _members[index];
              final profile = member['profiles'] ?? {};
              final weeklyIp = member['weekly_ip'] ?? 0;
              return ListTile(
                dense: true,
                title: Text('${profile['username'] ?? 'Ghost'} (${member['role'].toUpperCase()})', style: const TextStyle(color: Colors.white)),
                trailing: Text('$weeklyIp IP', style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
              );
            },
          ),
        ),
        const Divider(height: 1, color: Colors.redAccent),
        
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final msg = _messages[index];
              final metadata = msg['metadata'] as Map<String, dynamic>? ?? {};

              if (metadata['type'] == 'scrimmage_invite') {
                return _buildScrimmageBubble(msg, metadata);
              }

              final profile = msg['profiles'] ?? {};
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(
                  '${profile['username'] ?? 'Ghost'}: ${msg['message']}',
                  style: const TextStyle(color: Colors.white70),
                ),
              );
            },
          ),
        ),

        Container(
          padding: const EdgeInsets.all(8),
          color: Colors.grey[900],
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.sports_martial_arts, color: Colors.orangeAccent),
                onPressed: _showChallengeMenu,
              ),
              Expanded(
                child: TextField(
                  controller: _chatController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Send guild message...',
                    hintStyle: TextStyle(color: Colors.grey),
                    border: InputBorder.none,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send, color: Colors.redAccent),
                onPressed: _sendMessage,
              ),
            ],
          ),
        ),
        // Inside _buildGuildDashboard() in guild_screen.dart:
Container(
  padding: const EdgeInsets.all(12),
  color: Colors.grey[900],
  child: Column(
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Text('Level $guildLevel Guild', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
          Text('Shadows: $vaultShadows', style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Courier')),
          Text('Coins: $vaultCoins', style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontFamily: 'Courier')),
        ],
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.purpleAccent),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
        onPressed: () => _showTreasuryModal(context),
        icon: const Icon(Icons.account_balance, color: Colors.purpleAccent, size: 16),
        label: Text(
          isFounder ? 'MANAGE TREASURY & DOCTRINES' : 'VIEW GUILD VAULT',
          style: const TextStyle(color: Colors.purpleAccent, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Courier'),
        ),
      ),
    ],
  ),
),
      ],
    );
  }
}

// ==========================================
// OVERLAYS FOR SCRIMMAGES
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