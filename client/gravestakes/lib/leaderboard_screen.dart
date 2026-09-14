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

  String _playerSortMetric = 'lumen';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchLeaderboardData();
  }

  Future<void> _fetchLeaderboardData() async {
    if (mounted) setState(() => _isLoading = true);
    
    try {
      // 1. Fetch Top Players (Toggle between Lumen and Shadows)
      List<Map<String, dynamic>> playersRes;
      
      if (_playerSortMetric == 'lumen') {
        final res = await supabase
            .from('profiles')
            .select('username, level, lumen')
            .order('lumen', ascending: false)
            .limit(50);
        playersRes = List<Map<String, dynamic>>.from(res);
      } else {
        // Fallback to the old view if sorting by wealth
        final res = await supabase
            .from('leaderboard_view')
            .select('*')
            .order('shadows', ascending: false)
            .limit(50);
        playersRes = List<Map<String, dynamic>>.from(res);
      }

      // 2. Fetch Guilds (Ordered by collective wealth!)
      final guildsRes = await supabase
          .from('guild_leaderboard_view')
          .select('name, tag, member_count, total_shadows')
          .order('total_shadows', ascending: false)
          .limit(20);

      if (mounted) {
        setState(() {
          _topPlayers = playersRes;
          _topGuilds = List<Map<String, dynamic>>.from(guildsRes);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching leaderboard: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildPlayersList() {
    return Column(
      children: [
        // --- NEW: THE TOGGLE BAR ---
        Container(
          color: Colors.grey[900],
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('RANKED BY:', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _playerSortMetric,
                  dropdownColor: Colors.black,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Courier'),
                  icon: const Icon(Icons.arrow_drop_down, color: Colors.redAccent),
                  items: const [
                    DropdownMenuItem(value: 'lumen', child: Text('LUMEN (COMPETITIVE)')),
                    DropdownMenuItem(value: 'shadows', child: Text('SHADOWS (WEALTH)')),
                  ],
                  onChanged: (String? newValue) {
                    if (newValue != null && newValue != _playerSortMetric) {
                      setState(() {
                        _playerSortMetric = newValue;
                        _fetchLeaderboardData(); // Re-fetch when changed
                      });
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        // ---------------------------

        Expanded(
          child: _topPlayers.isEmpty
              ? const Center(child: Text('No ranked players found.', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: _topPlayers.length,
                  itemBuilder: (context, index) {
                    final player = _topPlayers[index];
                    final rank = index + 1;
                    final username = player['username'] ?? 'Unknown Ghost';
                    final level = player['level'] ?? 1;
                    
                    // --- NEW: DYNAMIC SCORE DISPLAY ---
                    final score = _playerSortMetric == 'lumen' ? (player['lumen'] ?? 0) : (player['shadows'] ?? 0);
                    final icon = _playerSortMetric == 'lumen' ? Icons.flash_on : Icons.nightlight_round;
                    final scoreColor = _playerSortMetric == 'lumen' ? Colors.yellowAccent : Colors.redAccent;
                    // ----------------------------------

                    Color rankColor = Colors.white54;
                    Color badgeBg = Colors.transparent;
                    if (rank == 1) {
                      rankColor = const Color(0xFFFFD700);
                      badgeBg = const Color(0xFFFFD700).withOpacity(0.12);
                    } else if (rank == 2) {
                      rankColor = const Color(0xFFC0C0C0);
                      badgeBg = const Color(0xFFC0C0C0).withOpacity(0.10);
                    } else if (rank == 3) {
                      rankColor = const Color(0xFFCD7F32);
                      badgeBg = const Color(0xFFCD7F32).withOpacity(0.10);
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: rank <= 3 ? badgeBg : Colors.grey[900],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: rank <= 3 ? rankColor.withOpacity(0.6) : Colors.white10,
                          width: rank <= 3 ? 1.5 : 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 38,
                            child: Text('#$rank', style: TextStyle(color: rankColor, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(username, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 2),
                                Text('LVL $level', style: const TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1.0)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: scoreColor.withOpacity(0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(icon, size: 13, color: scoreColor),
                                const SizedBox(width: 5),
                                Text('$score', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'Courier')),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
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

  Widget _buildGuildsList() {
    if (_topGuilds.isEmpty) {
      return const Center(child: Text('No guilds found.', style: TextStyle(color: Colors.grey))); //[cite: 4]
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), //[cite: 4]
      itemCount: _topGuilds.length, //[cite: 4]
      itemBuilder: (context, index) {
        final guild = _topGuilds[index]; //[cite: 4]
        final rank = index + 1; //[cite: 4]
        final name = guild['name'] ?? 'Unknown'; //[cite: 4]
        final tag = guild['tag'] ?? 'GHOST'; //[cite: 4]
        final totalShadows = guild['total_shadows'] ?? 0;
        final members = guild['member_count'] ?? 1;

        Color rankColor = Colors.white54;
        Color badgeBg = Colors.transparent;
        if (rank == 1) {
          rankColor = const Color(0xFFFFD700);
          badgeBg = const Color(0xFFFFD700).withOpacity(0.12);
        } else if (rank == 2) {
          rankColor = const Color(0xFFC0C0C0);
          badgeBg = const Color(0xFFC0C0C0).withOpacity(0.10);
        } else if (rank == 3) {
          rankColor = const Color(0xFFCD7F32);
          badgeBg = const Color(0xFFCD7F32).withOpacity(0.10);
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 8), //[cite: 4]
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), //[cite: 4]
          decoration: BoxDecoration(
            color: rank <= 3 ? badgeBg : Colors.grey[900], //[cite: 4]
            borderRadius: BorderRadius.circular(8), //[cite: 4]
            border: Border.all(
              color: rank <= 3 ? rankColor.withOpacity(0.6) : Colors.white10, //[cite: 4]
              width: rank <= 3 ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 38,
                child: Text(
                  '#$rank',
                  style: TextStyle(
                    color: rankColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Courier',
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '[$tag]',
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Courier',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$members MEMBERS',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.nightlight_round, size: 13, color: Colors.redAccent),
                    const SizedBox(width: 5),
                    Text(
                      '$totalShadows',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        fontFamily: 'Courier',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}