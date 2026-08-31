import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'progression_screen.dart';

class VesselOpenerOverlay extends StatefulWidget {
  final String vesselId;
  const VesselOpenerOverlay({super.key, required this.vesselId});

  static void show(BuildContext context, String vesselId) {
    showGeneralDialog(
      context: context,
      barrierColor: Colors.transparent, 
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, anim1, anim2) => VesselOpenerOverlay(vesselId: vesselId),
    );
  }

  @override
  State<VesselOpenerOverlay> createState() => _VesselOpenerOverlayState();
}

class _VesselOpenerOverlayState extends State<VesselOpenerOverlay> with TickerProviderStateMixin {
  late AnimationController _pressureController;
  late AnimationController _shakeController;
  
  bool _isOpened = false;
  bool _isFetching = false;
  List<Map<String, dynamic>> _rewards = [];
  
  final Random _random = Random();
  late Color _explosionColor;
  final List<VoidParticle> _particles = [];

  @override
  void initState() {
    super.initState();
    
    // Scale hold duration and colors based on vessel tier
    int durationMs = 1000;
    if (widget.vesselId == 'void_chrysalis') {
      _explosionColor = Colors.purpleAccent; // Legendary
      durationMs = 3000;
    } else if (widget.vesselId == 'soul_casket') {
      _explosionColor = Colors.redAccent; // Rare
      durationMs = 2000;
    } else {
      _explosionColor = Colors.cyanAccent; // Common
      durationMs = 1000; 
    }

    _pressureController = AnimationController(vsync: this, duration: Duration(milliseconds: durationMs));
    _shakeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 50))..repeat(reverse: true);

    _pressureController.addListener(() {
      setState(() {});
      if (_pressureController.value >= 1.0 && !_isOpened && !_isFetching) {
        _triggerBurst();
      }
    });
  }

  Future<void> _triggerBurst() async {
    setState(() {
      _isFetching = true;
      _isOpened = true;
      _generateExplosion();
    });

    try {
      final res = await Supabase.instance.client
          .rpc('open_vessel', params: {'p_vessel_id': widget.vesselId});
      
      if (res != null && (res as List).isNotEmpty) {
        // Now handles an array of multiple rewards returned from the database
        _rewards = List<Map<String, dynamic>>.from(res);
      }
    } catch (e) {
      debugPrint('Vessel Burst Error: $e');
      _rewards = [{'granted_reward_type': 'error', 'granted_reward_id': 'lost_soul', 'granted_amount': 0}];
    }
    
    setState(() { _isFetching = false; });
  }

  void _generateExplosion() {
    for (int i = 0; i < 60; i++) {
      double angle = _random.nextDouble() * 2 * pi;
      double speed = 5 + _random.nextDouble() * 25;
      _particles.add(VoidParticle(
        x: 0, y: 0, 
        vx: cos(angle) * speed, vy: sin(angle) * speed,
        size: 3 + _random.nextDouble() * 8,
        life: 1.0,
      ));
    }
  }

  void _onPointerDown(PointerDownEvent details) {
    if (!_isOpened) _pressureController.forward();
  }

  void _onPointerUp(PointerUpEvent details) {
    if (!_isOpened) _pressureController.reverse();
  }

  void _onPointerCancel(PointerCancelEvent details) {
    if (!_isOpened) _pressureController.reverse();
  }

  @override
  void dispose() {
    _pressureController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pressure = _pressureController.value;
    
    final shakeIntensity = pressure * 25.0;
    final shakeX = _isOpened ? 0.0 : (sin(_shakeController.value * pi * 2) * shakeIntensity);
    final shakeY = _isOpened ? 0.0 : (cos(_shakeController.value * pi * 2.7) * shakeIntensity);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Listener(
        onPointerDown: _onPointerDown,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: Stack(
          children: [
            Opacity(
              opacity: _isOpened ? 0.95 : 0.4 + (pressure * 0.5),
              child: Container(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.5,
                    colors: [Colors.black54, Colors.black],
                  ),
                ),
              ),
            ),
            Center(
              child: Transform.translate(
                offset: Offset(shakeX, shakeY),
                child: Transform.scale(
                  scale: _isOpened ? 1.0 : 1.0 + (pressure * 0.2),
                  child: _isOpened 
                    ? _buildRewardDisplay() 
                    : _buildProceduralMonolith(pressure),
                ),
              ),
            ),
            if (!_isOpened)
              Positioned(
                bottom: 100,
                left: 0, right: 0,
                child: Opacity(
                  opacity: 1.0 - pressure,
                  child: const Text(
                    'HOLD TO BREAK SEAL',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 18, letterSpacing: 4.0, fontFamily: 'Courier'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProceduralMonolith(double pressure) {
    return Container(
      width: 140, height: 220,
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: _explosionColor.withOpacity(0.1 + (pressure * 0.5)),
            blurRadius: 40 + (pressure * 60),
            spreadRadius: pressure * 20,
          )
        ],
      ),
      child: CustomPaint(
        painter: VesselPainter(widget.vesselId, pressure, _explosionColor),
      ),
    );
  }

  Widget _buildRewardDisplay() {
    return TweenAnimationBuilder(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 1200),
      builder: (context, val, child) {
        
        for (var p in _particles) {
          p.x += p.vx; p.y += p.vy;
          p.vy += 0.5; 
          p.life -= 0.02;
        }

        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            CustomPaint(
              painter: ParticlePainter(_particles, _explosionColor),
              size: const Size(1, 1),
            ),
            Transform.scale(
              scale: 1.5 - (val * 0.5), 
              child: Opacity(
                opacity: val,
                child: _isFetching 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'REWARDS RECOVERED',
                          style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2, fontFamily: 'Courier', shadows: [Shadow(color: Colors.black, blurRadius: 10)]),
                        ),
                        const SizedBox(height: 30),
                        // Dynamically render multiple rewards
                        Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          alignment: WrapAlignment.center,
                          children: _rewards.map((data) => RewardCard(rewardData: data)).toList(),
                        ),
                        const SizedBox(height: 50),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.black, side: BorderSide(color: _explosionColor, width: 2)),
                          onPressed: () {
                            // 1. Close the Vessel Opener dialog
                            Navigator.of(context).pop(); 
                            
                            // 2. Calculate totals from the rewards they just got
                            int totalCoins = 0;
                            int totalShadows = 0;
                            for (var reward in _rewards) {
                              if (reward['granted_reward_type'] == 'coins') totalCoins += (reward['granted_amount'] as int? ?? 0);
                              if (reward['granted_reward_type'] == 'shadows') totalShadows += (reward['granted_amount'] as int? ?? 0);
                            }

                            // 3. Push the new Progression Screen
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => ProgressionScreen(
                                  // Pass the actual totals you just pulled out of the chest
                                  shadowsEarned: totalShadows,
                                  coinsEarned: totalCoins,
                                  // For now, pass placeholder XP data (you can wire this to real DB stats later)
                                  oldXp: 400,
                                  newXp: 550,
                                  xpRequired: 1000,
                                ),
                              ),
                            );
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                            child: Text('ACCEPT', style: TextStyle(color: Colors.white, letterSpacing: 2, fontWeight: FontWeight.bold)),
                          ),
                        )
                      ],
                    ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// --- NEW COMPONENT: Handles the individual reward display and Shard-to-Coin conversion ---
class RewardCard extends StatefulWidget {
  final Map<String, dynamic> rewardData;
  const RewardCard({super.key, required this.rewardData});

  @override
  State<RewardCard> createState() => _RewardCardState();
}

class _RewardCardState extends State<RewardCard> {
  bool _isConverted = false;

  @override
  void initState() {
    super.initState();
    // If the database RPC flags this character shard as a duplicate, convert it after a brief delay
    final bool isDuplicate = widget.rewardData['is_duplicate'] == true;
    final String type = widget.rewardData['granted_reward_type'] ?? '';

    if (type == 'character_shard' && isDuplicate) {
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _isConverted = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final String type = widget.rewardData['granted_reward_type'] ?? 'unknown';
    final int amount = widget.rewardData['granted_amount'] ?? 0;
    final String label = (widget.rewardData['granted_reward_id'] ?? '').toString().toUpperCase();

    bool isShard = type == 'character_shard';
    Color baseColor = isShard ? Colors.cyanAccent : (type == 'coins' ? Colors.yellowAccent : Colors.purpleAccent);
    IconData icon = isShard ? Icons.person_add : (type == 'coins' ? Icons.monetization_on : Icons.diamond);

    // Swap styling if the duplicate shard converts to coins
    if (_isConverted) {
      baseColor = Colors.yellowAccent;
      icon = Icons.monetization_on;
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      transitionBuilder: (Widget child, Animation<double> animation) {
        // Flipping effect
        final rotate = Tween(begin: pi, end: 0.0).animate(animation);
        return AnimatedBuilder(
          animation: rotate,
          child: child,
          builder: (context, child) {
            final transform = Matrix4.rotationY(rotate.value);
            return Transform(transform: transform, alignment: Alignment.center, child: child);
          },
        );
      },
      child: Container(
        key: ValueKey<bool>(_isConverted),
        width: 130, height: 150,
        decoration: BoxDecoration(
          color: Colors.black87,
          border: Border.all(color: baseColor.withOpacity(0.8), width: 2),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: baseColor.withOpacity(0.3), blurRadius: 10)],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: baseColor),
            const SizedBox(height: 12),
            Text(
              _isConverted ? '+500' : '+$amount', // You can read the refund amount from DB payload as well
              style: TextStyle(color: baseColor, fontSize: 24, fontWeight: FontWeight.bold, fontFamily: 'Courier', shadows: const [Shadow(color: Colors.black, blurRadius: 4)]),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                _isConverted ? 'DUPLICATE\nREFUND' : label.replaceAll('_', ' '),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'Courier'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- EXISTING GRAPHICS COMPONENTS ---
class VoidParticle {
  double x, y, vx, vy, size, life;
  VoidParticle({required this.x, required this.y, required this.vx, required this.vy, required this.size, required this.life});
}

class ParticlePainter extends CustomPainter {
  final List<VoidParticle> particles;
  final Color baseColor;
  ParticlePainter(this.particles, this.baseColor);

  @override
  void paint(Canvas canvas, Size size) {
    for (var p in particles) {
      if (p.life <= 0) continue;
      final paint = Paint()
        ..color = baseColor.withOpacity(max(0, p.life))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);
      canvas.drawRect(Rect.fromCenter(center: Offset(p.x, p.y), width: p.size, height: p.size), paint);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class VesselPainter extends CustomPainter {
  final String vesselId;
  final double pressure;
  final Color baseColor;

  VesselPainter(this.vesselId, this.pressure, this.baseColor);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;
    
    final borderPaint = Paint()
      ..color = baseColor.withOpacity(0.5 + (pressure * 0.5))
      ..strokeWidth = 2 + (pressure * 4)
      ..style = PaintingStyle.stroke
      ..maskFilter = MaskFilter.blur(BlurStyle.solid, 2 + pressure * 4);

    if (vesselId == 'void_chrysalis') {
      final swell = pressure * 15;
      final rect = Rect.fromLTRB(
        size.width * 0.15 - swell, 
        size.height * 0.1 - swell, 
        size.width * 0.85 + swell, 
        size.height * 0.9 + swell * 0.5
      );
      final rrect = RRect.fromRectXY(rect, size.width * 0.4, size.height * 0.4);
      
      canvas.drawRRect(rrect, paint);
      canvas.drawRRect(rrect, borderPaint);

      final veinPaint = Paint()..color = baseColor.withOpacity(0.6)..style = PaintingStyle.stroke..strokeWidth = 2;
      final path = Path();
      path.moveTo(size.width * 0.5, size.height * 0.1 - swell);
      path.quadraticBezierTo(size.width * 0.2 - swell, size.height * 0.5, size.width * 0.5, size.height * 0.9 + swell * 0.5);
      path.moveTo(size.width * 0.5, size.height * 0.1 - swell);
      path.quadraticBezierTo(size.width * 0.8 + swell, size.height * 0.5, size.width * 0.5, size.height * 0.9 + swell * 0.5);
      canvas.drawPath(path, veinPaint);

    } else if (vesselId == 'soul_casket') {
      final path = Path();
      final swell = pressure * 8;
      
      path.moveTo(size.width * 0.3 - swell, size.height * 0.1);
      path.lineTo(size.width * 0.7 + swell, size.height * 0.1);
      path.lineTo(size.width * 0.9 + swell, size.height * 0.3);
      path.lineTo(size.width * 0.75, size.height * 0.9 + swell);
      path.lineTo(size.width * 0.25, size.height * 0.9 + swell);
      path.lineTo(size.width * 0.1 - swell, size.height * 0.3);
      path.close();
      
      canvas.drawPath(path, paint);
      canvas.drawPath(path, borderPaint);
      
      final chainPaint = Paint()..color = Colors.grey.shade800..style = PaintingStyle.stroke..strokeWidth = 4;
      canvas.drawLine(Offset(0, size.height * 0.4 + (sin(pressure * 20) * 5)), Offset(size.width, size.height * 0.45), chainPaint);
      canvas.drawLine(Offset(0, size.height * 0.7 + (cos(pressure * 20) * 5)), Offset(size.width, size.height * 0.65), chainPaint);

    } else {
      final path = Path();
      path.moveTo(size.width * 0.5, 0); 
      path.lineTo(size.width * 0.9 + (pressure * 15), size.height * 0.3);
      path.lineTo(size.width * 0.7, size.height);
      path.lineTo(size.width * 0.3, size.height);
      path.lineTo(size.width * 0.1 - (pressure * 15), size.height * 0.3);
      path.close();
      
      canvas.drawPath(path, paint);
      canvas.drawPath(path, borderPaint);

      canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.4), 15 + (pressure * 25), borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant VesselPainter oldDelegate) {
    return oldDelegate.pressure != pressure || oldDelegate.vesselId != vesselId;
  }
}