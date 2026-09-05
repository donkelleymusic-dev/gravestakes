import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:flame/game.dart';
import 'game.dart';
import 'store_screen.dart';
import 'loadout_screen.dart';
import 'friends_screen.dart';
import 'guild_screen.dart';
import 'leaderboard_screen.dart';
import 'party_screen.dart';
import 'spectator_mode.dart';
import 'match_summary_overlay.dart';
import 'vessel_opener_overlay.dart';
import 'level_up_overlay.dart';
import 'guild_war_map_screen.dart';
import 'guild_war_results_overlay.dart';
import 'audio_manager.dart';
import 'guild_war_results_overlay.dart';

class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  final supabase = Supabase.instance.client;
  // first run menu tutorial
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey _marketKey = GlobalKey();

  String _username = 'Loading...';
  int _level = 1;
  int _shadows = 0;
  int _coins = 0; 
  bool _isLoading = true;
  bool _isSearchingForMatch = false;
  String? _errorMessage;

  // first run menu tutorial
  final GlobalKey _loadoutKey = GlobalKey();
  final GlobalKey _startKey = GlobalKey();
  
  // Kept internally so backend RPC and game instances get a valid map key
  final String _selectedMapName = 'L1T1V1.0.0';
  
  String _selectedMatchMode = '1v1'; 

  Future<void> _checkTutorialPhase() async {
    final prefs = await SharedPreferences.getInstance();
    if (_level > 1) return; 

    final phase = prefs.getString('tutorial_phase') ?? 'market';
    
    // Wait for screen transitions to finish
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted || _scaffoldKey.currentContext == null) return;
      
      final showContext = _scaffoldKey.currentContext!;
      
      if (phase == 'market') {
        ShowCaseWidget.of(showContext).startShowCase([_marketKey]);
      } else if (phase == 'loadout') {
        ShowCaseWidget.of(showContext).startShowCase([_loadoutKey]);
      } else if (phase == 'match') {
        ShowCaseWidget.of(showContext).startShowCase([_startKey]);
      }
    });
  }

  Future<void> _checkPendingGuildWarRewards() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final pendingReward = await supabase
          .from('guild_war_rewards_queue')
          .select('*')
          .eq('user_id', user.id)
          .eq('claimed', false)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (pendingReward != null && mounted) {
        GuildWarResultsOverlay.show(
          context,
          pendingReward,
          () {
            // Callback fired after spoils are claimed
            _fetchPlayerData(); // Refreshes shadows, coins, and wallet display
          },
        );
      }
    } catch (e) {
      debugPrint('Error checking guild war rewards queue: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSavedPreferences();
    _fetchPlayerData();
    _checkPendingGuildWarRewards();
    _initMenuAudio(); // Initialize and play menu music
  }

  Future<void> _initMenuAudio() async {
    await AudioManager.instance.init();
    AudioManager.instance.playMenuMusic();
  }

  Future<void> _loadSavedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _selectedMatchMode = prefs.getString('last_match_mode') ?? '1v1';
      });
    }
  }

  Future<void> _fetchPlayerData() async {
    final user = supabase.auth.currentUser;
    
    if (user == null) {
      _logout();
      return; 
    }

    if (mounted) setState(() {
      _isLoading = true;
      _errorMessage = null; 
    });

    int maxRetries = 3;

    for (int i = 0; i < maxRetries; i++) {
      try {
        final responses = await Future.wait<dynamic>([
          supabase.from('profiles').select('username, level').eq('id', user.id).single(),
          supabase.from('wallets').select('shadows, coins').eq('id', user.id).single(),
        ]);

        // Inside _fetchPlayerData() in main_menu.dart, add this query check after fetching wallets/profiles:
        final rewardsRes = await supabase
            .from('guild_war_rewards_queue')
            .select('*')
            .eq('user_id', user.id)
            .eq('claimed', false)
            .maybeSingle();

        if (rewardsRes != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              GuildWarResultsOverlay.show(context, rewardsRes, () {
                _fetchPlayerData(); // Refresh player wallet after claiming
              });
            }
          });
        }

        final serverLevel = responses[0]['level'] ?? 1;

        final prefs = await SharedPreferences.getInstance();
        int lastSeenLevel = prefs.getInt('last_seen_level') ?? serverLevel;

        if (serverLevel > lastSeenLevel) {
          await prefs.setInt('last_seen_level', serverLevel);
          
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              LevelUpOverlay.show(context, serverLevel);
            }
          });
        } else {
          await prefs.setInt('last_seen_level', serverLevel);
        }

        if (mounted) {
          setState(() {
            _username = responses[0]['username'] ?? 'Ghost';
            _level = serverLevel;
            _shadows = responses[1]['shadows'] ?? 0;
            _coins = responses[1]['coins'] ?? 0; 
            _isLoading = false;
            _checkTutorialPhase();
          });
        }
        
        return; 

      } on PostgrestException catch (e) {
        if (e.code == 'PGRST303' && i < maxRetries - 1) {
          await Future.delayed(const Duration(milliseconds: 500));
          continue; 
        }
        
        if (e.code == '401' || e.code == '403' || e.code == 'PGRST301' || e.code == 'PGRST116') {
          debugPrint('Auth failure (${e.code}). Forcing logout...');
          _logout();
          return;
        }
        
        if (mounted) setState(() {
          _errorMessage = 'Server connection lost. (${e.code})';
          _isLoading = false;
        });
        return;
        
      } catch (e) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Network error. Please check your connection.';
            _isLoading = false;
          });
        }
        return;
      }
    }

  }

  Future<void> _findMatchAndStart(BuildContext context) async {
    debugPrint('--- CURRENT USER ID: ${supabase.auth.currentUser?.id} ---');
    if (_isSearchingForMatch) return;
    
    setState(() {
      _isSearchingForMatch = true;
    });

    try {
      int targetPlayers = 8;
      if (_selectedMatchMode == '1v1') targetPlayers = 2;
      if (_selectedMatchMode == '2v2') targetPlayers = 4;

      final gameInstance = GraveStakesGame(
        mapName: _selectedMapName,
        matchMode: _selectedMatchMode,
        targetPlayers: targetPlayers,
      );
      
      //await gameInstance.initAudioEngine();

      final response = await supabase.rpc(
        'find_or_create_match',
        params: {
          'p_map_name': _selectedMapName,
          'p_mode': _selectedMatchMode,
          'p_target_players': targetPlayers,
        }, 
      );
      
      gameInstance.roomId = response as String;

      // Stop menu music right before transitioning into the game
      AudioManager.instance.stopMusic();

      if (!context.mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => Scaffold(
            body: GameWidget<GraveStakesGame>(
              game: gameInstance,
              loadingBuilder: (context) => Container(
                color: Colors.black,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.redAccent),
                      SizedBox(height: 20),
                      Text(
                        'LOADING MAP...',
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
        _fetchPlayerData();
        _checkPendingGuildWarRewards(); // Checks queue if a season reset concluded during the match
      });
      
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST301' || e.code == '401' || e.code == 'PGRST116' || e.code == '42501') {
          debugPrint('Stale token or RLS block detected (${e.code}). Forcing logout...');
          _logout();
          return;
        }
      
      debugPrint('Matchmaking database error: ${e.message}');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Database error. Try again!')),
        );
      }
      
    } catch (e) {
      if (e is AuthException) {
        debugPrint('Auth exception during matchmaking. Forcing logout...');
        _logout();
        return; 
      }
      
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
    return ShowCaseWidget(
      builder: (context) => Scaffold(
        key: _scaffoldKey,
        backgroundColor: Colors.black,
        body: _isLoading
        ? const Center(child: CircularProgressIndicator(color: Colors.red))
        : _errorMessage != null
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.wifi_off, color: Colors.redAccent, size: 48),
                    const SizedBox(height: 16),
                    Text(_errorMessage!, style: const TextStyle(color: Colors.white, fontSize: 16)),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _fetchPlayerData,
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      label: const Text('RETRY CONNECTION', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red[800]),
                    ),
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: _logout,
                      child: const Text('LOGOUT', style: TextStyle(color: Colors.grey)),
                    ),
                  ],
                ),
              )
        : SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                            Text('${supabase.auth.currentUser?.email ?? 'Unknown'}', style: const TextStyle(color: Colors.yellowAccent, fontSize: 12)),
                            const SizedBox(height: 4),
                            Text('Level $_level', style: const TextStyle(color: Colors.grey, fontSize: 14)),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('Shadows: $_shadows', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text('Coins: $_coins', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 32),

                  // MATCH MODE SELECTOR DROPDOWN
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.purpleAccent),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedMatchMode,
                        dropdownColor: Colors.black87,
                        isExpanded: true,
                        style: const TextStyle(color: Colors.purpleAccent, fontFamily: 'Courier', fontWeight: FontWeight.bold),
                        items: const [
                          DropdownMenuItem(value: 'casual', child: Text('MODE: CASUAL FFA')),
                          DropdownMenuItem(value: '1v1', child: Text('MODE: 1v1 COMPETITIVE')),
                          DropdownMenuItem(value: '2v2', child: Text('MODE: 2v2 SQUAD BRAWL')),
                        ],
                        onChanged: (String? newValue) async {
                          if (newValue != null) {
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString('last_match_mode', newValue);
                            
                            setState(() {
                              _selectedMatchMode = newValue;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),

                  Showcase(
  key: _startKey,
  description: 'STEP 4: Select Casual Mode and Enter the Darkness!',
  targetShapeBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  disposeOnTap: true,
  onTargetClick: () => _findMatchAndStart(context),
  child:
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
                  const SizedBox(height: 12),

                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const SpectatorLobbyScreen()),
                      );
                    },
                    icon: const Icon(Icons.remove_red_eye, color: Colors.white),
                    label: const Text('SPECTATE MATCHES', style: TextStyle(color: Colors.white, fontSize: 16)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: Colors.grey),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),

                  const SizedBox(height: 24),
                  const Text('COMMUNITY & MANAGEMENT', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  const SizedBox(height: 12),

                  _buildMenuButton(
                    icon: Icons.local_fire_department,
                    label: 'CRYPT WAR MAP',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const GuildWarMapScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Showcase(
  key: _marketKey,
  description: 'STEP 1: Enter the Black Market to acquire your first mask.',
  disposeOnTap: true,
  onTargetClick: () {
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => const StoreScreen())).then((_) {
      _fetchPlayerData();
      _checkTutorialPhase(); // Re-check phase when returning
    });
  },
  child:_buildMenuButton(
                    icon: Icons.store,
                    label: 'THE BLACK MARKET',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const StoreScreen()),
                      ).then((_) => _fetchPlayerData());
                    },
                  ),
                  ),
                  const SizedBox(height: 10),
                  Showcase(
  key: _loadoutKey,
  description: 'STEP 3: Open your Bag Contents to equip your new mask.',
  disposeOnTap: true,
  onTargetClick: () {
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => const LoadoutScreen())).then((_) {
      _checkTutorialPhase();
    });
  },
  child:_buildMenuButton(
                    icon: Icons.backpack,
                    label: 'BAG CONTENTS',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const LoadoutScreen()),
                      );
                    },
                  ),
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

                  TextButton(
                    onPressed: _logout,
                    child: const Text('LOGOUT', style: TextStyle(color: Colors.grey)),
                  ),
                  const SizedBox(height: 20),
                ],
                ),
              ),
            ), // Closes Scaffold
          ), // Closes Builder
        ); // Closes ShowCaseWidget
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
              'SEARCHING FOR OPPONENTS...\n(${game.matchMode.toUpperCase()})',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2),
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