import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final supabase = Supabase.instance.client;
  final TextEditingController _codeController = TextEditingController();

  String _myFriendCode = 'Loading...';
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _pendingRequests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSocialData();
  }

  Future<void> _loadSocialData() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final profileRes = await supabase
          .from('profiles')
          .select('friend_code')
          .eq('id', user.id)
          .single();

      final friendshipsRes = await supabase
          .from('friendships')
          .select('id, user_id, friend_id, status')
          .or('user_id.eq.${user.id},friend_id.eq.${user.id}');

      List<Map<String, dynamic>> activeFriends = [];
      List<Map<String, dynamic>> pending = [];

      for (var f in friendshipsRes) {
        final otherId = f['user_id'] == user.id ? f['friend_id'] : f['user_id'];
        
        final otherProfile = await supabase
            .from('profiles')
            .select('id, username, level')
            .eq('id', otherId)
            .single();

        final friendData = {
          'friendship_id': f['id'],
          'id': otherProfile['id'],
          'username': otherProfile['username'] ?? 'Unknown',
          'level': otherProfile['level'] ?? 1,
        };

        if (f['status'] == 'accepted') {
          activeFriends.add(friendData);
        } else if (f['status'] == 'pending' && f['friend_id'] == user.id) {
          pending.add(friendData);
        }
      }

      if (mounted) {
        setState(() {
          _myFriendCode = profileRes['friend_code'] ?? 'UNKNOWN';
          _friends = activeFriends;
          _pendingRequests = pending;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading social data: $e');
    }
  }

  Future<void> _sendFriendRequest() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) return;

    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final targetProfile = await supabase
          .from('profiles')
          .select('id')
          .eq('friend_code', code)
          .maybeSingle();

      if (targetProfile == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid Friend Code! No ghost found.'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      final targetId = targetProfile['id'];
      if (targetId == user.id) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You cannot friend yourself!'), backgroundColor: Colors.orange),
          );
        }
        return;
      }

      await supabase.from('friendships').insert({
        'user_id': user.id,
        'friend_id': targetId,
        'status': 'pending',
      });

      _codeController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Friend request sent!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: Request already sent or failed.'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _acceptRequest(String friendshipId) async {
    try {
      await supabase
          .from('friendships')
          .update({'status': 'accepted'})
          .eq('id', friendshipId);

      _loadSocialData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Friend request accepted!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint('Error accepting request: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        title: const Text('FRIENDS & ALLIES', style: TextStyle(color: Colors.redAccent, letterSpacing: 1.5)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.red))
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('YOUR FRIEND CODE', style: TextStyle(color: Colors.grey, fontSize: 12)),
                            const SizedBox(height: 4),
                            Text(_myFriendCode, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2)),
                          ],
                        ),
                        const Icon(Icons.share, color: Colors.redAccent),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _codeController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Enter Friend Code (e.g., GHOST-1234)',
                            hintStyle: const TextStyle(color: Colors.grey),
                            filled: true,
                            fillColor: Colors.grey[900],
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red[800], padding: const EdgeInsets.all(16)),
                        onPressed: _sendFriendRequest,
                        child: const Text('ADD', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (_pendingRequests.isNotEmpty) ...[
                    const Text('PENDING REQUESTS', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 80,
                      child: ListView.builder(
                        itemCount: _pendingRequests.length,
                        itemBuilder: (context, index) {
                          final req = _pendingRequests[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(color: Colors.grey[950], borderRadius: BorderRadius.circular(6)),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('${req['username']} (Lv. ${req['level']})', style: const TextStyle(color: Colors.white)),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                                  onPressed: () => _acceptRequest(req['friendship_id']),
                                  child: const Text('ACCEPT', style: TextStyle(color: Colors.white)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  const Text('FRIENDS LIST', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _friends.isEmpty
                        ? const Center(child: Text('No friends added yet. Share your code!', style: TextStyle(color: Colors.grey)))
                        : ListView.builder(
                            itemCount: _friends.length,
                            itemBuilder: (context, index) {
                              final friend = _friends[index];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.grey[900],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(friend['username'], style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 4),
                                        const Text('Level • Online', style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
                                      ],
                                    ),
                                    const Icon(Icons.bolt, color: Colors.redAccent),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}