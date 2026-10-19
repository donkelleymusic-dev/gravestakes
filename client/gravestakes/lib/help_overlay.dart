import 'package:flutter/material.dart';

class HelpZone {
  final String title;
  final String text;
  final Offset Function() getTargetCenter;

  HelpZone({
    required this.title, 
    required this.text, 
    required this.getTargetCenter
  });
}

class InteractiveHelpOverlay extends StatefulWidget {
  final List<HelpZone> zones;
  final VoidCallback onClose;

  const InteractiveHelpOverlay({super.key, required this.zones, required this.onClose});

  @override
  State<InteractiveHelpOverlay> createState() => _InteractiveHelpOverlayState();
}

class _InteractiveHelpOverlayState extends State<InteractiveHelpOverlay> with SingleTickerProviderStateMixin {
  HelpZone? _activeZone;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.85),
      child: Stack(
        children: [
          // 1. Invisible touch layer to dismiss active tooltip if tapped elsewhere
          GestureDetector(
            onTap: () => setState(() => _activeZone = null),
            behavior: HitTestBehavior.opaque,
            child: Container(),
          ),
          
          // 2. The Interactive Pulsing Hotspots (Dynamically Positioned!)
          ...widget.zones.map((zone) {
            bool isActive = _activeZone == zone;
            
            // Fire the function to calculate exact screen coordinates at runtime
            Offset center;
            try {
               center = zone.getTargetCenter();
            } catch (e) {
               center = Offset(MediaQuery.of(context).size.width / 2, MediaQuery.of(context).size.height / 2);
            }

            return Positioned(
              left: center.dx - 30, // Shift by half width to center the 60x60 node
              top: center.dy - 30,
              child: GestureDetector(
                onTap: () => setState(() => _activeZone = zone),
                child: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isActive ? Colors.cyanAccent.withOpacity(0.4) : Colors.cyanAccent.withOpacity(_pulseController.value * 0.3),
                        border: Border.all(color: Colors.cyanAccent, width: isActive ? 3 : 1.5),
                      ),
                      child: const Icon(Icons.touch_app, color: Colors.white70, size: 24),
                    );
                  }
                ),
              ),
            );
          }),

          // 3. The Central Tooltip Box
          if (_activeZone != null)
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 40),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.cyanAccent, width: 2),
                  boxShadow: [BoxShadow(color: Colors.cyanAccent.withOpacity(0.3), blurRadius: 20)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _activeZone!.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.cyanAccent, fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Orbitron', letterSpacing: 2),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _activeZone!.text,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontFamily: 'Orbitron', height: 1.4),
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.cyanAccent)),
                      onPressed: () => setState(() => _activeZone = null),
                      child: const Text('GOT IT', style: TextStyle(color: Colors.cyanAccent, fontFamily: 'Orbitron', fontWeight: FontWeight.bold)),
                    )
                  ],
                ),
              ),
            ),

          // 4. The Exit "X" Button
          Positioned(
            top: 16,
            right: 16,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.redAccent, size: 36),
                onPressed: widget.onClose,
              ),
            ),
          ),
          
          // 5. Initial instruction text
          if (_activeZone == null)
            const Center(
              child: Text(
                'TAP A GLOWING NODE\nTO REVEAL ITS SECRETS',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 3, fontFamily: 'Orbitron'),
              ),
            )
        ],
      ),
    );
  }
}