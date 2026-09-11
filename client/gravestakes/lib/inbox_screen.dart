import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'theme.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchMessages();
  }

  Future<void> _fetchMessages() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final response = await supabase
          .from('player_inbox')
          .select('id, sender_id, message_type, template_key, attached_image_url, is_read, is_actioned, created_at, profiles!sender_id(username)')
          .eq('recipient_id', userId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _messages = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }

      // Mark all fetched messages as read in the background
      final unreadIds = _messages.where((m) => m['is_read'] == false).map((m) => m['id']).toList();
      if (unreadIds.isNotEmpty) {
        await supabase.from('player_inbox').update({'is_read': true}).inFilter('id', unreadIds);
      }
    } catch (e) {
      debugPrint('Error fetching inbox: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String currentLang = context.locale.languageCode;

    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        title: Text(
          'INBOX', 
          style: AppTheme.getLocalizedStyle(currentLang, color: Colors.purpleAccent, fontWeight: FontWeight.bold, letterSpacing: 2.0)
        ),
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.purpleAccent))
          : _messages.isEmpty
              ? Center(
                  child: Text(
                    'Your inbox is empty.',
                    style: AppTheme.getLocalizedStyle(currentLang, color: Colors.white54, fontSize: 16),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    return InboxMessageCard(
                      messageData: _messages[index],
                      onActionComplete: _fetchMessages, // Refresh list when accepted
                    );
                  },
                ),
    );
  }
}

class InboxMessageCard extends StatefulWidget {
  final Map<String, dynamic> messageData;
  final VoidCallback onActionComplete;

  const InboxMessageCard({super.key, required this.messageData, required this.onActionComplete});

  @override
  State<InboxMessageCard> createState() => _InboxMessageCardState();
}

class _InboxMessageCardState extends State<InboxMessageCard> {
  bool _isProcessing = false;

  Future<void> _acceptFriendRequest() async {
    setState(() => _isProcessing = true);
    final supabase = Supabase.instance.client;
    final myId = supabase.auth.currentUser?.id;
    final senderId = widget.messageData['sender_id'];
    final messageId = widget.messageData['id'];

    if (myId == null || senderId == null) return;

    try {
      // 1. Accept the friendship (assuming sender created the pending request)
      await supabase
          .from('friendships')
          .update({'status': 'accepted'})
          .match({'requester_id': senderId, 'addressee_id': myId});

      // 2. Mark the message as actioned so the button disappears
      await supabase
          .from('player_inbox')
          .update({'is_actioned': true})
          .eq('id', messageId);

      widget.onActionComplete();
    } catch (e) {
      debugPrint('Failed to accept friend request: $e');
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String currentLang = context.locale.languageCode;
    
    final templateKey = widget.messageData['template_key'] ?? 'unknown_msg';
    final imageUrl = widget.messageData['attached_image_url'];
    final messageType = widget.messageData['message_type'];
    final isActioned = widget.messageData['is_actioned'] ?? false;
    
    // Safely extract sender username
    final profiles = widget.messageData['profiles'];
    final senderName = (profiles is Map && profiles.containsKey('username')) 
        ? profiles['username'] 
        : 'Unknown Entity';

    return Card(
      color: Colors.black54,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Colors.white24), 
        borderRadius: BorderRadius.circular(8)
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.vertical(top: Radius.circular(8))
            ),
            child: Text(
              'From: $senderName', 
              style: AppTheme.getLocalizedStyle(currentLang, color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          
          // Attached Polaroid
          if (imageUrl != null)
            Image.network(
              imageUrl, 
              height: 250, 
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                height: 100, 
                color: Colors.grey[900], 
                child: const Center(child: Icon(Icons.broken_image, color: Colors.white24))
              ),
            ),
          
          // Translated Text Payload
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              templateKey.tr(), // Magic translation happens here!
              style: AppTheme.getLocalizedStyle(currentLang, color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),

          // Action Buttons (e.g., Accept Friend Request)
          if (messageType == 'friend_request' && !isActioned)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _isProcessing 
                ? const Center(child: CircularProgressIndicator(color: Colors.purpleAccent))
                : ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple[800],
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _acceptFriendRequest,
                    icon: const Icon(Icons.handshake, color: Colors.white),
                    label: Text(
                      'btn_accept'.tr(), 
                      style: AppTheme.getLocalizedStyle(currentLang, color: Colors.white, fontWeight: FontWeight.bold)
                    ),
                  ),
            )
          else if (messageType == 'friend_request' && isActioned)
             Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Text(
                'REQUEST ACCEPTED', 
                textAlign: TextAlign.center,
                style: AppTheme.getLocalizedStyle(currentLang, color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            )
        ],
      ),
    );
  }
}

class ComposeMessageDialog extends StatefulWidget {
  const ComposeMessageDialog({super.key});

  @override
  State<ComposeMessageDialog> createState() => _ComposeMessageDialogState();
}

class _ComposeMessageDialogState extends State<ComposeMessageDialog> {
  final supabase = Supabase.instance.client;
  List<Map<String, String>> _friends = [];
  String? _selectedFriendId;
  bool _isLoading = true;
  bool _isSending = false;

  final List<String> _templates = [
    'respect_victory',
    'wwe_revenge_promise',
    'territory_challenge',
    'scrimmage_challenge'
  ];
  String _selectedTemplate = 'respect_victory';

  @override
  void initState() {
    super.initState();
    _fetchFriends();
  }

  Future<void> _fetchFriends() async {
    final myId = supabase.auth.currentUser?.id;
    if (myId == null) return;

    try {
      // Fetch where status is accepted and the user is either requester or addressee
      final response = await supabase
          .from('friendships')
          .select('requester_id, addressee_id, requester:profiles!requester_id(username), addressee:profiles!addressee_id(username)')
          .eq('status', 'accepted')
          .or('requester_id.eq.$myId,addressee_id.eq.$myId');

      final List<Map<String, String>> parsedFriends = [];
      for (var row in response) {
        final isRequester = row['requester_id'] == myId;
        final friendId = isRequester ? row['addressee_id'] : row['requester_id'];
        final friendData = isRequester ? row['addressee'] : row['requester'];
        
        parsedFriends.add({
          'id': friendId,
          'username': friendData['username'] ?? 'Unknown',
        });
      }

      if (mounted) {
        setState(() {
          _friends = parsedFriends;
          if (_friends.isNotEmpty) _selectedFriendId = _friends.first['id'];
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching friends: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendMessage() async {
    if (_selectedFriendId == null) return;
    
    setState(() => _isSending = true);
    final myId = supabase.auth.currentUser!.id;

    try {
      await supabase.from('player_inbox').insert({
        'recipient_id': _selectedFriendId,
        'sender_id': myId,
        'message_type': 'direct_message',
        'template_key': _selectedTemplate,
      });

      if (mounted) Navigator.of(context).pop(true); // Return true to trigger inbox refresh
    } catch (e) {
      debugPrint('Error sending message: $e');
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String currentLang = context.locale.languageCode;

    return AlertDialog(
      backgroundColor: Colors.black87,
      shape: RoundedRectangleBorder(side: const BorderSide(color: Colors.purpleAccent), borderRadius: BorderRadius.circular(8)),
      title: Text('DISPATCH MESSAGE', style: AppTheme.getLocalizedStyle(currentLang, color: Colors.white, fontWeight: FontWeight.bold)),
      content: _isLoading 
        ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator(color: Colors.purpleAccent)))
        : _friends.isEmpty
            ? Text('You have no allies to message.', style: AppTheme.getLocalizedStyle(currentLang, color: Colors.white54))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Select Ally:', style: AppTheme.getLocalizedStyle(currentLang, color: Colors.grey, fontSize: 12)),
                  DropdownButton<String>(
                    isExpanded: true,
                    dropdownColor: Colors.grey[900],
                    value: _selectedFriendId,
                    items: _friends.map((f) => DropdownMenuItem(
                      value: f['id'],
                      child: Text(f['username']!, style: AppTheme.getLocalizedStyle(currentLang, color: Colors.cyanAccent)),
                    )).toList(),
                    onChanged: (val) => setState(() => _selectedFriendId = val),
                  ),
                  const SizedBox(height: 16),
                  
                  Text('Select Dispatch:', style: AppTheme.getLocalizedStyle(currentLang, color: Colors.grey, fontSize: 12)),
                  DropdownButton<String>(
                    isExpanded: true,
                    dropdownColor: Colors.grey[900],
                    value: _selectedTemplate,
                    items: _templates.map((t) => DropdownMenuItem(
                      value: t,
                      child: Text(t.tr(), style: AppTheme.getLocalizedStyle(currentLang, color: Colors.white, fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis),
                    )).toList(),
                    onChanged: (val) => setState(() => _selectedTemplate = val!),
                  ),
                ],
              ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('CANCEL', style: AppTheme.getLocalizedStyle(currentLang, color: Colors.white54)),
        ),
        if (_friends.isNotEmpty)
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple[800]),
            onPressed: _isSending ? null : _sendMessage,
            child: _isSending 
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Text('SEND', style: AppTheme.getLocalizedStyle(currentLang, color: Colors.white, fontWeight: FontWeight.bold)),
          ),
      ],
    );
  }
}