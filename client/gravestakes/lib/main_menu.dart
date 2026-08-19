import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flame/game.dart';
import 'game.dart';
import 'store_screen.dart';
import 'loadout_screen.dart';
import 'friends_screen.dart';
import 'guild_screen.dart';
import 'leaderboard_screen.dart';
import 'party_screen.dart';

class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  final supabase = Supabase.instance.client;
  
  String _username = 'Loading...';
  int _level = 1;
  int _shadows = 0;
  int _stakes = 0;
  bool _isLoading = true;
  bool _isSearchingForMatch = false;

  @override
  void initState() {
    super.initState();
    _fetchPlayerData();
  }

  Future<void> _fetchPlayerData() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    int maxRetries = 3;

    for (int i = 0; i < maxRetries; i++) {
      try {
        final responses = await Future.wait<dynamic>([
          supabase.from('profiles').select('username, level').eq('id', user.id).single(),
          supabase.from('wallets').select('shadows, stakes').eq('id', user.id).single(),
        ]);

        if (mounted) {
          setState(() {
            _username = responses[0]['username'] ?? 'Ghost';
            _level = responses[0]['level'] ?? 1;
            _shadows = responses[1]['shadows'] ?? 0;
            _stakes = responses[1]['stakes'] ?? 0;
            _isLoading = false;
          });
        }
        
        break; 

      } on PostgrestException catch (e) {
        if (e.code == 'PGRST303' && i < maxRetries - 1) {
          debugPrint('Supabase clock drift detected (Attempt ${i + 1}). Waiting 500ms and retrying...');
          await Future.delayed(const Duration(milliseconds: 500));
          continue; 
        }
        
        debugPrint('Database error: ${e.message}');
        if (mounted) setState(() => _isLoading = false); 
        break;
        
      } catch (e) {
        debugPrint('Error fetching menu data: $e');
        if (mounted) setState(() => _isLoading = false);
        break;
      }
    }
  }

  Future<void> _findMatchAndStart(BuildContext context) async {
    if (_isSearchingForMatch) return;
    
    setState(() {
      _isSearchingForMatch = true;
    });

    try {
      final response = await supabase.rpc('find_or_create_match');
      final String safeRoomId = response as String;

      if (!context.mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => Scaffold(
            body: GameWidget(game: GraveStakesGame(roomId: safeRoomId)),
          ),
        ),
      ).then((_) {
        _fetchPlayerData();
      });
    } catch (e) {
      debugPrint('Matchmaking failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to find a match. Try again!')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSearchingForMatch = false;
        });
      }
    }
  }

  void _logout() async {
    await supabase.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Colors.red))
        : SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // TOP BAR: Player Stats
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
                            Text(_username, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text('Level $_level', style: const TextStyle(color: Colors.grey, fontSize: 14)),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('Shadows: $_shadows', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text('Stakes: $_stakes', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 32),

                  // CENTER: Matchmaking & Party Buttons
                  ElevatedButton(
                    onPressed: () => _findMatchAndStart(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[800],
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(
                      _isSearchingForMatch ? 'SEARCHING...' : 'FIND MATCH',
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 2),
                    ),
                  ),
                  
                  const SizedBox(height: 12),

                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const PartyScreen()),
                      ).then((_) => _fetchPlayerData());
                    },
                    icon: const Icon(Icons.group, color: Colors.white),
                    label: const Text('SQUAD PARTY', style: TextStyle(color: Colors.white, fontSize: 16)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: Colors.grey),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),

                  const SizedBox(height: 24),
                  const Text('COMMUNITY & MANAGEMENT', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  const SizedBox(height: 12),

                  // VERTICAL STACKED NAVIGATION BUTTONS
                  _buildMenuButton(
                    icon: Icons.store,
                    label: 'THE BLACK MARKET',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const StoreScreen()),
                      ).then((_) => _fetchPlayerData());
                    },
                  ),
                  const SizedBox(height: 10),
                  _buildMenuButton(
                    icon: Icons.backpack,
                    label: 'LOADOUT',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const LoadoutScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  _buildMenuButton(
                    icon: Icons.people,
                    label: 'FRIENDS',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const FriendsScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  _buildMenuButton(
                    icon: Icons.shield,
                    label: 'GUILDS',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const GuildScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  _buildMenuButton(
                    icon: Icons.leaderboard,
                    label: 'LEADERBOARD',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const LeaderboardScreen()),
                      );
                    },
                  ),

                  const SizedBox(height: 32),

                  // BOTTOM: Logout
                  TextButton(
                    onPressed: _logout,
                    child: const Text('LOGOUT', style: TextStyle(color: Colors.grey)),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildMenuButton({required IconData icon, required String label, required VoidCallback onPressed}) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: Colors.white),
      label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        side: const BorderSide(color: Colors.grey),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}