import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VesselOpenerOverlay extends StatefulWidget {
  final String vesselId;
  const VesselOpenerOverlay({super.key, required this.vesselId});

  // Easy helper to pop this open over your game
  static void show(BuildContext context, String vesselId) {
    showGeneralDialog(
      context: context,
      barrierColor: Colors.transparent, // We handle the dark fade manually!
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
  Map<String, dynamic>? _rewardData;
  
  final Random _random = Random();
  late Color _explosionColor;
  final List<VoidParticle> _particles = [];

  @override
  void initState() {
    super.initState();
    // Color-code the explosion and vessel based on the tier!
    if (widget.vesselId == 'void_chrysalis') {
      _explosionColor = Colors.purpleAccent;
    } else if (widget.vesselId == 'soul_casket') {
      _explosionColor = Colors.redAccent;
    } else {
      _explosionColor = Colors.cyanAccent; // shadow_reliquary
    }

    _pressureController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000));
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
      // Call your backend RPC!
      final res = await Supabase.instance.client
          .rpc('open_vessel', params: {'p_vessel_id': widget.vesselId});
      
      if (res != null && (res as List).isNotEmpty) {
        _rewardData = res.first;
      }
    } catch (e) {
      debugPrint('Vessel Burst Error: $e');
      _rewardData = {'granted_reward_type': 'error', 'granted_reward_id': 'lost_soul', 'granted_amount': 0};
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
    
    // Procedural Shake Math
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
            // 1. The Breathing Dark Cloud Background
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

            // 2. The Vessel / Explosion System
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

            // 3. Instruction Text
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
          // This keeps the glowing aura behind the vessel
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
        
        // Animate particles outward
        for (var p in _particles) {
          p.x += p.vx; p.y += p.vy;
          p.vy += 0.5; // Gravity
          p.life -= 0.02;
        }

        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Procedural Particle Blast
            CustomPaint(
              painter: ParticlePainter(_particles, _explosionColor),
              size: const Size(1, 1),
            ),
            
            // The Loot Text Slam
            Transform.scale(
              scale: 1.5 - (val * 0.5), // Slams down from huge to normal
              child: Opacity(
                opacity: val,
                child: _isFetching 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '+${_rewardData?['granted_amount'] ?? 0}',
                          style: const TextStyle(
                            color: Colors.white, fontSize: 72, fontWeight: FontWeight.bold,
                            shadows: [Shadow(color: Colors.black, blurRadius: 20)],
                          ),
                        ),
                        Text(
                          (_rewardData?['granted_reward_id'] ?? 'UNKNOWN').toString().toUpperCase(),
                          style: TextStyle(
                            color: _explosionColor, fontSize: 28, letterSpacing: 8,
                            shadows: const [Shadow(color: Colors.black, blurRadius: 10)],
                          ),
                        ),
                        const SizedBox(height: 60),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.black, side: BorderSide(color: _explosionColor)),
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('ACCEPT', style: TextStyle(color: Colors.white, letterSpacing: 2)),
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
      // THE ANOMALY: A pulsating, biological egg/cocoon
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

      // Draw organic inner veins that stretch as pressure increases
      final veinPaint = Paint()..color = baseColor.withOpacity(0.6)..style = PaintingStyle.stroke..strokeWidth = 2;
      final path = Path();
      path.moveTo(size.width * 0.5, size.height * 0.1 - swell);
      path.quadraticBezierTo(size.width * 0.2 - swell, size.height * 0.5, size.width * 0.5, size.height * 0.9 + swell * 0.5);
      path.moveTo(size.width * 0.5, size.height * 0.1 - swell);
      path.quadraticBezierTo(size.width * 0.8 + swell, size.height * 0.5, size.width * 0.5, size.height * 0.9 + swell * 0.5);
      canvas.drawPath(path, veinPaint);

    } else if (vesselId == 'soul_casket') {
      // THE REVENANT: A heavy, chained coffin
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
      
      // Draw bindings/chains across the casket that snap and shake with pressure
      final chainPaint = Paint()..color = Colors.grey.shade800..style = PaintingStyle.stroke..strokeWidth = 4;
      canvas.drawLine(Offset(0, size.height * 0.4 + (sin(pressure * 20) * 5)), Offset(size.width, size.height * 0.45), chainPaint);
      canvas.drawLine(Offset(0, size.height * 0.7 + (cos(pressure * 20) * 5)), Offset(size.width, size.height * 0.65), chainPaint);

    } else {
      // THE FLICKER: A sharp, jagged shadow reliquary (Diamond / Obelisk)
      final path = Path();
      path.moveTo(size.width * 0.5, 0); // Top point
      path.lineTo(size.width * 0.9 + (pressure * 15), size.height * 0.3);
      path.lineTo(size.width * 0.7, size.height);
      path.lineTo(size.width * 0.3, size.height);
      path.lineTo(size.width * 0.1 - (pressure * 15), size.height * 0.3);
      path.close();
      
      canvas.drawPath(path, paint);
      canvas.drawPath(path, borderPaint);

      // Inner glowing core
      canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.4), 15 + (pressure * 25), borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant VesselPainter oldDelegate) {
    return oldDelegate.pressure != pressure || oldDelegate.vesselId != vesselId;
  }
}