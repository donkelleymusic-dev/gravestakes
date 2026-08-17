import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  late TabController _tabController;

  bool _isLoading = true;
  List<Map<String, dynamic>> _topPlayers = [];
  List<Map<String, dynamic>> _topGuilds = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchLeaderboardData();
  }

  Future<void> _fetchLeaderboardData() async {
    try {
      // 1. Fetch top players from our database view
      final playersRes = await supabase.from('leaderboard_view').select('*');

      // 2. Fetch top guilds
      final guildsRes = await supabase.from('guilds').select('name, tag, created_at').limit(20);

      if (mounted) {
        setState(() {
          _topPlayers = List<Map<String, dynamic>>.from(playersRes);
          _topGuilds = List<Map<String, dynamic>>.from(guildsRes);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching leaderboard: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        title: const Text('HALL OF FAME', style: TextStyle(color: Colors.redAccent, letterSpacing: 1.5)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.redAccent,
          labelColor: Colors.redAccent,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: 'TOP GHOSTS'),
            Tab(text: 'TOP GUILDS'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.red))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildPlayersList(),
                _buildGuildsList(),
              ],
            ),
    );
  }

  Widget _buildPlayersList() {
    if (_topPlayers.isEmpty) {
      return const Center(child: Text('No ranked players found.', style: TextStyle(color: Colors.grey)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _topPlayers.length,
      itemBuilder: (context, index) {
        final player = _topPlayers[index];
        final rank = index + 1;
        final username = player['username'] ?? 'Unknown Ghost';
        final level = player['level'] ?? 1;
        final shadows = player['shadows'] ?? 0;

        Color rankColor = Colors.grey;
        if (rank == 1) rankColor = Colors.amber;
        if (rank == 2) rankColor = Colors.grey.shade300;
        if (rank == 3) rankColor = Colors.brown.shade300;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: rank <= 3 ? rankColor.withOpacity(0.5) : Colors.transparent),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text('#$rank', style: TextStyle(color: rankColor, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(username, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text('Level $level', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ],
              ),
              Text('$shadows Shadows', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGuildsList() {
    if (_topGuilds.isEmpty) {
      return const Center(child: Text('No guilds found.', style: TextStyle(color: Colors.grey)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _topGuilds.length,
      itemBuilder: (context, index) {
        final guild = _topGuilds[index];
        final rank = index + 1;
        final name = guild['name'] ?? 'Unknown';
        final tag = guild['tag'] ?? 'GHOST';

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
              Row(
                children: [
                  Text('#$rank', style: const TextStyle(color: Colors.grey, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 16),
                  Text('$name [$tag]', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              const Text('Active', style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
            ],
          ),
        );
      },
    );
  }
}