import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    final messagesRes = await supabase
        .from('guild_messages')
        .select('id, message, sender_id, created_at, profiles(username)')
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
        event: PostgresChangeEvent.insert,
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

  // CONTEXT-SENSITIVE LEAVE / DISBAND DIALOG
  Future<void> _promptLeaveOrDisband() async {
    final user = supabase.auth.currentUser;
    if (user == null || _myGuild == null) return;

    final bool isFounder = _myGuild!['founder_id'] == user.id;
    final otherMembers = _members.where((m) => m['user_id'] != user.id).toList();

    if (!isFounder) {
      // SCENARIO 1: Regular Member
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text('Leave Guild?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: const Text(
            'Are you sure you want to leave this guild? You will lose access to guild chat and perks.',
            style: TextStyle(color: Colors.grey),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('CANCEL', style: TextStyle(color: Colors.grey))),
            TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('LEAVE', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
          ],
        ),
      );

      if (confirmed == true) {
        _executeRegularLeave(user.id);
      }
    } else if (otherMembers.isEmpty) {
      // SCENARIO 2: Founder, but solo (no other members)
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text('Disband Guild?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: const Text(
            'You are the last member in this guild. Leaving will permanently disband and delete the guild.',
            style: TextStyle(color: Colors.grey),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('CANCEL', style: TextStyle(color: Colors.grey))),
            TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('DISBAND', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
          ],
        ),
      );

      if (confirmed == true) {
        _executeDisband();
      }
    } else {
      // SCENARIO 3: Founder with active members -> Choose a successor!
      String? selectedSuccessorId = otherMembers.first['user_id'];

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setStateDialog) {
              return AlertDialog(
                backgroundColor: Colors.grey[900],
                title: const Text('Appoint Successor & Leave', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'You are the guild leader and other members are still in the guild. You must appoint a new leader before you can leave.',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    const Text('Select New Leader:', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      dropdownColor: Colors.grey[850],
                      value: selectedSuccessorId,
                      items: otherMembers.map((m) {
                        final profile = m['profiles'] ?? {};
                        return DropdownMenuItem<String>(
                          value: m['user_id'] as String,
                          child: Text(profile['username'] ?? 'Ghost', style: const TextStyle(color: Colors.white)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setStateDialog(() {
                          selectedSuccessorId = val;
                        });
                      },
                    ),
                  ],
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('CANCEL', style: TextStyle(color: Colors.grey))),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('PROMOTE & LEAVE', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                  ),
                ],
              );
            },
          );
        },
      );

      if (confirmed == true && selectedSuccessorId != null) {
        _executeTransferAndLeave(user.id, selectedSuccessorId!);
      }
    }
  }

  Future<void> _executeRegularLeave(String userId) async {
    try {
      _chatChannel?.unsubscribe();
      await supabase.from('guild_members').delete().eq('user_id', userId);
      setState(() {
        _myGuild = null;
        _isLoading = true;
      });
      _loadGuildData();
    } catch (e) {
      debugPrint('Error leaving guild: $e');
    }
  }

  Future<void> _executeDisband() async {
    try {
      _chatChannel?.unsubscribe();
      await supabase.from('guilds').delete().eq('id', _myGuild!['id']);
      setState(() {
        _myGuild = null;
        _isLoading = true;
      });
      _loadGuildData();
    } catch (e) {
      debugPrint('Error disbanding guild: $e');
    }
  }

  Future<void> _executeTransferAndLeave(String currentUserId, String newLeaderId) async {
    try {
      _chatChannel?.unsubscribe();

      // 1. Promote new leader in members table
      await supabase.from('guild_members')
          .update({'role': 'founder'})
          .eq('guild_id', _myGuild!['id'])
          .eq('user_id', newLeaderId);

      // 2. Update the founder reference on the guild record
      await supabase.from('guilds')
          .update({'founder_id': newLeaderId})
          .eq('id', _myGuild!['id']);

      // 3. Remove current user from the guild
      await supabase.from('guild_members')
          .delete()
          .eq('user_id', currentUserId);

      setState(() {
        _myGuild = null;
        _isLoading = true;
      });
      _loadGuildData();
    } catch (e) {
      debugPrint('Error transferring leadership: $e');
    }
  }

  Future<void> _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty || _myGuild == null) return;

    final user = supabase.auth.currentUser;
    if (user == null) return;

    final moderatedText = _bleepText(text);

    // Clear the text field immediately so it feels snappy
    _chatController.clear();

    try {
      await supabase.from('guild_messages').insert({
        'guild_id': _myGuild!['id'],
        'sender_id': user.id,
        'message': moderatedText,
      });

      // INSTANT LOCAL REFRESH: Don't wait for the realtime broadcast to tell us 
      // about our own message. Fetch it immediately!
      await _fetchMessages(_myGuild!['id']);
      
    } catch (e) {
      debugPrint('Error sending message: $e');
    }
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
            child: const Text('FOUND GUILD', style: TextStyle(color: Colors.white)),
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

  Widget _buildGuildDashboard() {
    return Column(
      children: [
        Container(
          height: 120,
          padding: const EdgeInsets.all(8),
          color: Colors.grey[950],
          child: ListView.builder(
            itemCount: _members.length,
            itemBuilder: (context, index) {
              final member = _members[index];
              final profile = member['profiles'] ?? {};
              return ListTile(
                dense: true,
                title: Text('${profile['username'] ?? 'Ghost'} (${member['role'].toUpperCase()})', style: const TextStyle(color: Colors.white)),
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
      ],
    );
  }
}