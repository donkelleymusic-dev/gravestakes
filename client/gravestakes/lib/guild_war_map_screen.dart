import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GuildWarMapScreen extends StatefulWidget {
  const GuildWarMapScreen({super.key});

  @override
  State<GuildWarMapScreen> createState() => _GuildWarMapScreenState();
}

class _GuildWarMapScreenState extends State<GuildWarMapScreen> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _nodes = [];
  bool _isPrimeTime = false;
  Map<String, dynamic>? _myGuild;

  @override
  void initState() {
    super.initState();
    _loadWarData();
  }

  Future<void> _loadWarData() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final nodesRes = await supabase
          .from('guild_nodes')
          .select('*, guilds(name, tag)')
          .order('node_name');

      final membership = await supabase
          .from('guild_members')
          .select('guild_id, guilds(*)')
          .eq('user_id', user.id)
          .maybeSingle();

      // Fetch authoritative state from database config table
      final configRes = await supabase
          .from('guild_war_config')
          .select('is_prime_time_active')
          .eq('id', 1)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _nodes = List<Map<String, dynamic>>.from(nodesRes);
          if (membership != null) {
            _myGuild = membership['guilds'];
          }
          _isPrimeTime = configRes != null ? (configRes['is_prime_time_active'] ?? false) : false;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading Guild War map: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showScheduleDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('CRYPT WAR SCHEDULE', style: TextStyle(color: Colors.redAccent, fontFamily: 'Courier', fontWeight: FontWeight.bold)),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Daily Prime-Time Window:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
            SizedBox(height: 4),
            Text('• 18:00 UTC - 20:00 UTC Daily (Cron Controlled)', style: TextStyle(color: Colors.grey, fontFamily: 'Courier')),
            SizedBox(height: 16),
            Text('Prime-Time Benefits:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
            SizedBox(height: 4),
            Text('• 3x IP Multiplier on all 2v2 matches\n• Direct Contested Node Overrides when clashing with rival guild squads', style: TextStyle(color: Colors.grey, fontFamily: 'Courier')),
            SizedBox(height: 16),
            Text('Weekly Reset:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
            SizedBox(height: 4),
            Text('• Every Sunday at 00:00 UTC\n• Territory control and Vault dividends distribute automatically on login', style: TextStyle(color: Colors.grey, fontFamily: 'Courier')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('CLOSE', style: TextStyle(color: Colors.redAccent, fontFamily: 'Courier', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        title: const Text('CRYPT RESONATOR WAR', style: TextStyle(color: Colors.redAccent, letterSpacing: 1.5, fontFamily: 'Courier')),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: InkWell(
                onTap: () => _showScheduleDialog(context),
                child: Chip(
                  backgroundColor: _isPrimeTime ? Colors.red[900] : Colors.grey[800],
                  label: Text(
                    _isPrimeTime ? '🔥 PRIME-TIME ACTIVE (Tap Schedule)' : '⏰ STANDARD HOURS (Tap Schedule)',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Courier'),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.red))
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.grey[950],
                  width: double.infinity,
                  child: const Text(
                    'Grind matches in Casual or 1v1 to generate IP. Squad up in 2v2 during Prime-Time to trigger Contested Node Overrides!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 12, fontFamily: 'Courier'),
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: _nodes.length,
                    itemBuilder: (context, index) {
                      final node = _nodes[index];
                      final guild = node['guilds'] as Map<String, dynamic>?;
                      final isControlledByMe = _myGuild != null && guild != null && guild['id'] == _myGuild!['id'];

                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[900],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isControlledByMe ? Colors.cyanAccent : (guild != null ? Colors.redAccent : Colors.white24),
                            width: isControlledByMe ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              node['node_name'] ?? 'Crypt Node',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'Courier'),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Buff: ${node['buff_type'] ?? 'Passive Boost'}',
                              style: const TextStyle(color: Colors.yellowAccent, fontSize: 10, fontFamily: 'Courier'),
                            ),
                            const Spacer(),
                            const Divider(color: Colors.white24),
                            const SizedBox(height: 4),
                            const Text('CONTROLLER:', style: TextStyle(color: Colors.grey, fontSize: 9, fontFamily: 'Courier')),
                            const SizedBox(height: 2),
                            Text(
                              guild != null ? '${guild['name']} [${guild['tag']}]' : 'UNCLAIMED',
                              style: TextStyle(
                                color: isControlledByMe ? Colors.cyanAccent : (guild != null ? Colors.white : Colors.grey),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                fontFamily: 'Courier',
                              ),
                            ),
                            const SizedBox(height: 6),
                            LinearProgressIndicator(
                              value: ((node['current_ip'] ?? 0) / 10000.0).clamp(0.0, 1.0),
                              color: Colors.redAccent,
                              backgroundColor: Colors.black,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Influence: ${node['current_ip']} IP',
                              style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'Courier'),
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
}