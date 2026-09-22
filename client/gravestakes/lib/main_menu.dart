import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:flame/game.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'voxel_character_component.dart';
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
import 'crypt_pass_screen.dart';
import 'match_summary_screen.dart';
import 'inbox_screen.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'cinematic_trailer_game.dart';
import 'lumen_tier_system.dart';
import 'synth_manager.dart';
import 'vanity_screen.dart';

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

  // --- The Static Session Flag (Prevents Double Rewards) ---
  static bool _hasCheckedLoginRewards = false;

  // --- The Ambient Background Engine ---
  late final AmbientMenuGame _ambientGame;

  String _username = 'Loading...';
  int _level = 1;
  int _shadows = 0;
  int _coins = 0; 
  int _unclaimedPassTiers = 0;
  int _freeMarketItems = 0;
  bool _isLoading = true;
  bool _isSearchingForMatch = false;
  String? _errorMessage;
  int _lumen = 0;
  bool _completedTutorial = false;

  final GlobalKey _loadoutKey = GlobalKey();
  final GlobalKey _startKey = GlobalKey();
  
  final String _selectedMapName = 'L1T1V1.0.0';
  String _selectedMatchMode = '1v1'; 

  Future<void> _checkTutorialPhase() async {
    final prefs = await SharedPreferences.getInstance();

    // NEW: If the server says we are done, permanently silence the local phase.
    if (_completedTutorial || _level > 1) {
      await prefs.setString('tutorial_phase', 'completed');
      return;
    }

    final phase = prefs.getString('tutorial_phase') ?? 'market';
    if (phase == 'completed') return;
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
            _fetchPlayerData(); 
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
    
    // Initialize the background game
    _ambientGame = AmbientMenuGame();
    
    if (!_hasCheckedLoginRewards) {
      _hasCheckedLoginRewards = true;
      _checkPendingGuildWarRewards();
    }
    
    _fetchPlayerData();
    _initMenuAudio(); 
  }

  Future<void> _initMenuAudio() async {
    debugPrint('MainMenu: _initMenuAudio() started.');
    try {
      await Future.wait([
        AudioManager.instance.init(),
        SynthManager.instance.init(),
      ]);
      debugPrint('MainMenu: Both Audio and Synth managers initialized successfully.');
      AudioManager.instance.playMenuMusic();
    } catch (e) {
      debugPrint('MainMenu ERROR: Something crashed inside _initMenuAudio(): $e');
    }
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

    try {
      await Purchases.logIn(user.id);
    } catch (e) {
      debugPrint('RevenueCat login failed: $e');
    }
    
    if (mounted) setState(() {
      _isLoading = true;
      _errorMessage = null; 
    });

    int maxRetries = 3;
    for (int i = 0; i < maxRetries; i++) {
      try {
        final responses = await Future.wait<dynamic>([
          supabase.from('profiles').select('username, level, lumen, completed_tutorial').eq('id', user.id).single(),
          supabase.from('wallets').select('shadows, coins').eq('id', user.id).single(),
        ]);

        final seasonRes = await supabase.from('season_config').select('id').eq('is_active', true).maybeSingle();
        int unclaimedTiers = 0;
        if (seasonRes != null) {
          final progressRes = await supabase
              .from('player_season_progress')
              .select('current_tier, highest_claimed_tier')
              .eq('user_id', user.id)
              .eq('season_id', seasonRes['id'])
              .maybeSingle();

          if (progressRes != null) {
            int currentTier = progressRes['current_tier'] ?? 0;
            int highestClaimed = progressRes['highest_claimed_tier'] ?? 0;
            if (currentTier > highestClaimed) {
              unclaimedTiers = currentTier - highestClaimed;
            }
          }
        }

        final serverLevel = responses[0]['level'] ?? 1;
        final prefs = await SharedPreferences.getInstance();
        int lastSeenLevel = prefs.getInt('last_seen_level') ?? serverLevel;

        int freeMarketItems = 0;
        final lastClaimIso = prefs.getString('last_free_drop_${user.id}');

        if (lastClaimIso == null) {
          freeMarketItems = 1;
        } else {
          final lastClaimTime = DateTime.parse(lastClaimIso);
          final nextAvailable = lastClaimTime.add(const Duration(hours: 12));
          if (nextAvailable.difference(DateTime.now()).isNegative) {
            freeMarketItems = 1;
          }
        }

        if (serverLevel > lastSeenLevel) {
          await prefs.setInt('last_seen_level', serverLevel);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) LevelUpOverlay.show(context, serverLevel);
          });
        } else {
          await prefs.setInt('last_seen_level', serverLevel);
        }

        if (mounted) {
          setState(() {
            _username = responses[0]['username'] ?? 'Ghost';
            _level = serverLevel;
            _lumen = responses[0]['lumen'] ?? 0;
            _completedTutorial = responses[0]['completed_tutorial'] ?? false;
            _shadows = responses[1]['shadows'] ?? 0;
            _coins = responses[1]['coins'] ?? 0; 
            _unclaimedPassTiers = unclaimedTiers;
            _freeMarketItems = freeMarketItems;
            _isLoading = false;
            _checkTutorialPhase();
          });
          Sentry.configureScope((scope) {
            scope.setUser(SentryUser(id: user.id, username: _username));
          });
        }
        return; 

      } on PostgrestException catch (e) {
        if (e.code == 'PGRST303' && i < maxRetries - 1) {
          await Future.delayed(const Duration(milliseconds: 500));
          continue; 
        }
        if (e.code == '401' || e.code == '403' || e.code == 'PGRST301' || e.code == 'PGRST116') {
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
    if (_isSearchingForMatch) return;
    setState(() => _isSearchingForMatch = true);

    try {
      int targetPlayers = 8;
      if (_selectedMatchMode == '1v1') targetPlayers = 2;
      if (_selectedMatchMode == '2v2') targetPlayers = 4;

      final gameInstance = GraveStakesGame(
        mapName: _selectedMapName,
        matchMode: _selectedMatchMode,
        targetPlayers: targetPlayers,
      );

      Sentry.configureScope((scope) {
        scope.setTag('match_mode', _selectedMatchMode);
        scope.setTag('map_name', _selectedMapName);
      });

      final response = await supabase.rpc(
        'find_or_create_match',
        params: {
          'p_map_name': _selectedMapName,
          'p_mode': _selectedMatchMode,
          'p_target_players': targetPlayers,
        }, 
      );
      
      gameInstance.roomId = response as String;
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
        _checkPendingGuildWarRewards(); 
      });
      
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST301' || e.code == '401' || e.code == 'PGRST116' || e.code == '42501') {
          _logout();
          return;
        }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Database error. Try again!')));
      }
    } catch (e) {
      if (e is AuthException) {
        _logout();
        return; 
      }
      Sentry.captureMessage('Matchmaking failed: $e', level: SentryLevel.warning);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to find a match. Try again!')));
      }
    } finally {
      if (mounted) setState(() => _isSearchingForMatch = false);
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
                    child: Stack(
                      children: [
                        // --- 1. BRANDING LOGO (BEHIND THE ENGINE) ---
                        Positioned(
                          bottom: 160, // Increased from 130 to clear the dropdown menu!
                          left: 80,    
                          right: 80,   
                          child: IgnorePointer(
                            child: Opacity(
                              opacity: 0.6, 
                              child: Image.asset(
                                'assets/images/Lumen_Breach_small.jpg',
                                fit: BoxFit.contain, 
                              ),
                            ),
                          ),
                        ),

                        // --- 2. 3D FPS AMBIENT BACKGROUND GAME ---
                        Positioned.fill(
                          child: IgnorePointer(
                            child: GameWidget(game: _ambientGame),
                          ),
                        ),
                        
                        // --- 3. TOP LEFT: PLAYER PROFILE ---
                        Positioned(
                          top: 16,
                          left: 16,
                          child: _buildProfileBadge(),
                        ),
                        
                        // --- TOP RIGHT: WALLET & LOGOUT ---
                        Positioned(
                          top: 16,
                          right: 16,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildWalletBadge(),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.logout, color: Colors.white54),
                                onPressed: _logout,
                                tooltip: 'Logout',
                              ),
                            ],
                          ),
                        ),

                        // --- LEFT EDGE: SOCIAL & RANKING ---
                        Positioned(
                          top: 120,
                          left: 16,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildSidebarIcon(icon: Icons.people, color: Colors.cyanAccent, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FriendsScreen()))),
                              _buildSidebarIcon(icon: Icons.shield, color: Colors.blueAccent, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GuildScreen()))),
                              _buildSidebarIcon(icon: Icons.leaderboard, color: Colors.yellowAccent, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LeaderboardScreen()))),
                            ],
                          ),
                        ),

                        // --- RIGHT EDGE: EVENTS, SETTINGS & INBOX ---
                        Positioned(
                          top: 120,
                          right: 16,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildSidebarIcon(icon: Icons.mail_outline, color: Colors.white, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InboxScreen()))),
                              _buildSidebarIcon(icon: Icons.settings, color: Colors.grey, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()))),
                              _buildSidebarIcon(icon: Icons.local_fire_department, color: Colors.orangeAccent, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GuildWarMapScreen()))),
                              _buildSidebarIcon(icon: Icons.card_membership, color: Colors.purpleAccent, badgeCount: _unclaimedPassTiers, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CryptPassScreen())).then((_) => _fetchPlayerData())),
                              
                              // --- NEW: LINK TO THE ECHO CHAMBER (VANITY HUB) ---
                              _buildSidebarIcon(
                                icon: Icons.auto_awesome, 
                                color: Colors.pinkAccent, 
                                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VanityScreen())).then((_) => _fetchPlayerData()),
                              ),
                            ],
                          ),
                        ),

                        // --- SECRET DEV BUTTON ---
                        if (supabase.auth.currentUser?.email == 'donkelleymusic@gmail.com')
                          Positioned(
                            top: 16,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: IconButton(
                                icon: const Icon(Icons.movie_creation, color: Colors.greenAccent, size: 24),
                                onPressed: () {
                                  SynthManager.instance.playMagicTap();
                                  Future.delayed(const Duration(milliseconds: 25), () {
                                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => Scaffold(body: GameWidget(game: GraveStakesGame(matchMode: 'cinematic')))));
                                  });
                                },
                              ),
                            ),
                          ),

                        // --- BOTTOM LEFT: SECONDARY ACTIONS ---
                        Positioned(
                          bottom: 130,
                          left: 16,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildSidebarIcon(icon: Icons.group, color: Colors.white70, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PartyScreen())).then((_) => _fetchPlayerData())),
                              _buildSidebarIcon(icon: Icons.remove_red_eye, color: Colors.white70, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SpectatorLobbyScreen()))),
                              if (GraveStakesGame.lastMatchPhotos.isNotEmpty)
                                _buildSidebarIcon(icon: Icons.photo_library, color: Colors.pinkAccent, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MatchSummaryScreen(photos: GraveStakesGame.lastMatchPhotos)))),
                            ],
                          ),
                        ),

                        // --- BOTTOM CENTER: THE ACTION HUB ---
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 24.0, left: 16, right: 16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // LEFT: THE CRYPT
                                Showcase(
                                  key: _loadoutKey,
                                  description: 'STEP 3: Enter The Crypt to equip your new mask.',
                                  disposeOnTap: true,
                                  onTargetClick: () {
                                    SynthManager.instance.playMagicTap();
                                    Future.delayed(const Duration(milliseconds: 25), () {
                                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoadoutScreen())).then((_) => _checkTutorialPhase());
                                    });
                                  },
                                  child: _buildChunkyButton(
                                    icon: Icons.backpack, 
                                    label: 'btn_crypt'.tr(), 
                                    color: Colors.cyanAccent, 
                                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoadoutScreen())),
                                  ),
                                ),

                                // CENTER: MATCHMAKING
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          height: 36,
                                          padding: const EdgeInsets.symmetric(horizontal: 12),
                                          decoration: BoxDecoration(
                                            color: Colors.black87,
                                            borderRadius: BorderRadius.circular(18),
                                            border: Border.all(color: Colors.purpleAccent.withOpacity(0.5)),
                                          ),
                                          child: DropdownButtonHideUnderline(
                                            child: DropdownButton<String>(
                                              value: _selectedMatchMode,
                                              dropdownColor: Colors.black,
                                              icon: const Icon(Icons.arrow_drop_down, color: Colors.purpleAccent),
                                              style: const TextStyle(color: Colors.purpleAccent, fontFamily: 'Courier', fontWeight: FontWeight.bold, fontSize: 12),
                                              items: const [
                                                DropdownMenuItem(value: 'casual', child: Text('CASUAL FFA')),
                                                DropdownMenuItem(value: '1v1', child: Text('1v1 RANKED')),
                                                DropdownMenuItem(value: '2v2', child: Text('2v2 SQUAD')),
                                              ],
                                              onChanged: (String? newValue) async {
                                                if (newValue != null) {
                                                  SynthManager.instance.playMagicTap();
                                                  final prefs = await SharedPreferences.getInstance();
                                                  await prefs.setString('last_match_mode', newValue);
                                                  setState(() => _selectedMatchMode = newValue);
                                                }
                                              },
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        
                                        Showcase(
                                          key: _startKey,
                                          description: 'STEP 8: Select Casual Mode and Enter the Darkness!',
                                          disposeOnTap: true,
                                          onTargetClick: () async {
                                            SynthManager.instance.playMagicTap();
                                            Future.delayed(const Duration(milliseconds: 25), () async {
                                              final prefs = await SharedPreferences.getInstance();
                                              await prefs.setString('tutorial_phase', 'completed');
                                              try {
                                                if (supabase.auth.currentUser?.id != null) {
                                                  await supabase.from('profiles').update({'completed_tutorial': true}).eq('id', supabase.auth.currentUser!.id);
                                                  _completedTutorial = true;
                                                }
                                              } catch (e) {}
                                              if (mounted) _findMatchAndStart(context);
                                            });
                                          },
                                          child: GestureDetector(
                                            onTap: () async {
                                              SynthManager.instance.playMagicTap();
                                              Future.delayed(const Duration(milliseconds: 25), () async {
                                                try {
                                                  final prefs = await SharedPreferences.getInstance();
                                                  if (prefs.getString('tutorial_phase') == 'match') await prefs.setString('tutorial_phase', 'completed');
                                                } catch (e) {}
                                                if (mounted) _findMatchAndStart(context);
                                              });
                                            },
                                            child: Container(
                                              height: 70,
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(colors: [Colors.red.shade900, Colors.redAccent]),
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(color: Colors.white54, width: 2),
                                                boxShadow: [BoxShadow(color: Colors.redAccent.withOpacity(0.5), blurRadius: 15)],
                                              ),
                                              child: Center(
                                                child: Text(
                                                  _isSearchingForMatch ? 'btn_searching'.tr() : 'btn_find_match'.tr(),
                                                  textAlign: TextAlign.center, 
                                                  style: const TextStyle(
                                                    color: Colors.white, 
                                                    fontSize: 18, 
                                                    fontWeight: FontWeight.bold, 
                                                    letterSpacing: 2, 
                                                    fontFamily: 'Courier', 
                                                    shadows: [Shadow(color: Colors.black, blurRadius: 4)]
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                // RIGHT: MARKET
                                Showcase(
                                  key: _marketKey,
                                  description: 'STEP 1: Enter the Black Market for your first supply drop.',
                                  disposeOnTap: true,
                                  onTargetClick: () {
                                    SynthManager.instance.playMagicTap();
                                    Future.delayed(const Duration(milliseconds: 25), () {
                                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StoreScreen())).then((_) {
                                        _fetchPlayerData();
                                        _checkTutorialPhase();
                                      });
                                    });
                                  },
                                  child: _buildChunkyButton(
                                    icon: Icons.store, 
                                    label: 'btn_black_market'.tr(), 
                                    color: Colors.amberAccent, 
                                    badgeCount: _freeMarketItems,
                                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StoreScreen())).then((_) => _fetchPlayerData()),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }

  // --- UI WIDGET BUILDERS ---
  Widget _buildSidebarIcon({required IconData icon, required Color color, required VoidCallback onTap, int badgeCount = 0}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: GestureDetector(
        onTap: () {
          SynthManager.instance.playMagicTap();
          Future.delayed(const Duration(milliseconds: 25), onTap);
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.grey[900]?.withOpacity(0.8),
                shape: BoxShape.circle,
                border: Border.all(color: color.withOpacity(0.5), width: 2),
                boxShadow: [BoxShadow(color: color.withOpacity(0.1), blurRadius: 8)],
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            if (badgeCount > 0)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                  child: Text('$badgeCount', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildChunkyButton({required IconData icon, required String label, required Color color, required VoidCallback onTap, int badgeCount = 0}) {
    return GestureDetector(
      onTap: () {
        SynthManager.instance.playMagicTap();
        Future.delayed(const Duration(milliseconds: 25), onTap);
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 75,
            height: 75,
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.8), width: 2),
              boxShadow: [BoxShadow(color: color.withOpacity(0.2), blurRadius: 10)],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(height: 4),
                Text(
                  label, 
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold, fontFamily: 'Courier'),
                ),
              ],
            ),
          ),
          if (badgeCount > 0)
            Positioned(
              top: -6,
              right: -6,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                child: Text('$badgeCount', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProfileBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: Colors.grey[800], shape: BoxShape.circle, border: Border.all(color: Colors.cyanAccent)),
            child: Center(child: Text('$_level', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_username, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Icon(LumenSystem.getTier(_lumen).icon, color: LumenSystem.getTier(_lumen).color, size: 10),
                  const SizedBox(width: 4),
                  Text('${LumenSystem.getTier(_lumen).name} ($_lumen)', style: TextStyle(color: LumenSystem.getTier(_lumen).color, fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWalletBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$_shadows', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(width: 4),
              const Icon(Icons.dark_mode, color: Colors.redAccent, size: 14),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$_coins', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(width: 4),
              const Icon(Icons.monetization_on, color: Colors.amberAccent, size: 14),
            ],
          ),
        ],
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
            const SizedBox(height: 32),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.redAccent),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: () => Navigator.of(context).pop(), 
              icon: const Icon(Icons.close, color: Colors.redAccent),
              label: const Text('CANCEL MATCHMAKING', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
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

// --- NEW: THE TRUE 3D FPS PERSPECTIVE ENGINE (WITH FOG) ---
class AmbientMenuGame extends FlameGame {
  double _spawnTimer = 3.0; 
  double _fogTimer = 0.0;
  final math.Random random = math.Random();
  List<Map<String, dynamic>> availableCharacters = [];

  @override
  Color backgroundColor() => Colors.transparent;

  @override
  Future<void> onLoad() async {
    try {
      final res = await Supabase.instance.client.from('characters').select('id, base_speed');
      availableCharacters = List<Map<String, dynamic>>.from(res);
    } catch (e) {}

    // Pre-warm the environment with fog so it isn't empty on load
    for (int i = 0; i < 25; i++) {
      add(MenuFog(initialZ: random.nextDouble() * 1000.0));
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    
    // 1. Monster Spawner
    _spawnTimer -= dt;
    if (_spawnTimer <= 0) {
      _spawnRunner();
      _spawnTimer = 8.0 + random.nextDouble() * 7.0; 
    }

    // 2. Fog Spawner (Continuously rolls in from the horizon)
    _fogTimer -= dt;
    if (_fogTimer <= 0) {
      add(MenuFog(initialZ: 1000.0));
      _fogTimer = 0.2 + random.nextDouble() * 0.4; 
    }
  }

  void _spawnRunner() async {
    String charId = 'default';
    double speed = 200.0;
    
    if (availableCharacters.isNotEmpty) {
      final charData = availableCharacters[random.nextInt(availableCharacters.length)];
      charId = charData['id'] ?? 'default';
      speed = (charData['base_speed'] as num?)?.toDouble() ?? 200.0;
    }

    await GraveStakesGame.ensureCharacterLoaded(charId);

    final rig = GraveStakesGame.characterRigCache[charId] ?? GraveStakesGame.characterRigCache['default'];
    final images = GraveStakesGame.characterImagesCache[charId] ?? GraveStakesGame.characterImagesCache['default'];

    if (rig != null && images != null) {
      add(MenuRunner(images: images, rig: rig, speed: speed));
    }
  }
}

// --- NEW: 3D VOLUMETRIC FOG ---
class MenuFog extends PositionComponent with HasGameReference<AmbientMenuGame> {
  double worldX = 0;        
  double worldZ;   
  double speedZ = 30.0;
  double driftX = 0.0;
  double baseRadius = 150.0;

  MenuFog({required double initialZ}) : worldZ = initialZ;

  @override
  Future<void> onLoad() async {
    anchor = Anchor.center;
    // Spread them widely across the horizon
    worldX = (game.random.nextDouble() * 1200.0) - 600.0;
    
    // Slow, drifting speeds
    speedZ = 20.0 + game.random.nextDouble() * 30.0;
    driftX = (game.random.nextDouble() * 20.0) - 10.0;
    
    // Massive cloud sizes
    baseRadius = 150.0 + game.random.nextDouble() * 200.0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    
    worldZ -= speedZ * dt;
    worldX += driftX * dt;
    
    // Despawn when it flows past the camera
    if (worldZ <= -50.0) {
      removeFromParent();
      return;
    }

    double z = math.max(worldZ, 10.0); 
    double fov = 400.0; 
    double perspective = fov / z;

    double horizonY = game.size.y * 0.25; 
    double cameraHeight = 100.0; // Slightly lower than monsters to hug the ground         

    double screenX = (game.size.x / 2) + (worldX * perspective);
    double screenY = horizonY + (cameraHeight * perspective);

    position = Vector2(screenX, screenY);
    scale = Vector2.all(perspective); 
    
    // Exactly matches the monster priority math for perfect depth sorting!
    priority = (perspective * 1000).toInt();
  }

  @override
  void render(Canvas canvas) {
    // Fade in from the deep black horizon, and fade out slightly as it hits the camera
    double distanceFade = ((worldZ - 50) / 500).clamp(0.0, 1.0);
    double opacity = 0.12 * distanceFade;

    // A radial gradient is incredibly cheap to render compared to a blur filter
    final paint = Paint()
      ..shader = ui.Gradient.radial(
        Offset.zero,
        baseRadius,
        [Colors.grey.withOpacity(opacity), Colors.grey.withOpacity(0.0)],
        [0.0, 1.0],
      );
      
    canvas.drawCircle(Offset.zero, baseRadius, paint);
  }
}

class MenuRunner extends PositionComponent with HasGameReference<AmbientMenuGame> {
  final Map<String, ui.Image> images;
  final Map<String, dynamic> rig;
  final double speed;
  late VoxelCharacterComponent voxel;

  double worldX = 0;        
  double worldZ = 1000.0;   
  double speedZ = 200.0;    

  MenuRunner({required this.images, required this.rig, required this.speed});

  @override
  Future<void> onLoad() async {
    voxel = VoxelCharacterComponent(
      images: images,
      rigData: rig,
      hitboxSize: Vector2.all(32),
    );
    voxel.isMoving = true;
    voxel.targetAngle = math.pi; 
    
    add(voxel);
    anchor = Anchor.bottomCenter;

    worldZ = 1000.0; 
    double side = game.random.nextBool() ? 1.0 : -1.0;
    worldX = side * (50.0 + game.random.nextDouble() * 200.0);
    speedZ = speed * 1.5; 
  }

  // --- NEW: LOCAL TIME DILATION ---
  @override
  void updateTree(double dt) {
    // 1. Calculate progress from 0.0 (distant) to 1.0 (at camera)
    double progress = ((1000.0 - worldZ) / 1050.0).clamp(0.0, 1.0);
    
    // 2. The Semi-Exponential Curve
    // math.pow(progress, 2.0) curves gently at the start, then spikes.
    // 1.0 base speed + up to 1.0 extra speed = 2.0x max speed!
    double timeMultiplier = 1.0 + math.pow(progress, 2.0);
    
    // 3. Pass the accelerated time to this component and its Voxel child
    super.updateTree(dt * timeMultiplier);
  }

  @override
  void update(double dt) {
    super.update(dt);
    
    // dt is ALREADY scaled by updateTree, so travel speed naturally increases!
    worldZ -= speedZ * dt;
    
    if (worldZ <= -50.0) {
      removeFromParent();
      return;
    }

    double z = math.max(worldZ, 10.0); 
    double fov = 400.0; 
    double perspective = fov / z;

    double horizonY = game.size.y * 0.25; 
    double cameraHeight = 120.0;          

    double screenX = (game.size.x / 2) + (worldX * perspective);
    double screenY = horizonY + (cameraHeight * perspective);

    position = Vector2(screenX, screenY);
    
    double baseScale = perspective * 3.5;
    scale = Vector2.all(baseScale + math.pow(perspective, 2.0) * 0.1); 
    
    priority = (perspective * 1000).toInt();
  }

  @override
  void render(Canvas canvas) {
    // Fades IN slowly from Z=1000 down to Z=300 (A long, 700-unit fade)
    double fadeIn = ((1000.0 - worldZ) / 700.0).clamp(0.0, 1.0);
    
    // Fades OUT quickly from Z=200 down to Z=-50
    double fadeOut = ((worldZ + 50.0) / 250.0).clamp(0.0, 1.0);
    
    double ghostOpacity = math.min(fadeIn, fadeOut);

    double darknessAmount = ((worldZ - 400) / 600).clamp(0.0, 1.0);
    
    canvas.saveLayer(
      Rect.fromLTWH(-1000, -1000, 2000, 2000), 
      Paint()
        ..color = Colors.white.withOpacity(ghostOpacity)
        ..colorFilter = ColorFilter.mode(
          Colors.black.withOpacity(darknessAmount), 
          BlendMode.srcATop
        ),
    );
    
    super.render(canvas);
    
    canvas.restore();
  }
}