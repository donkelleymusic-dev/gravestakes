import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'game.dart';
import 'voxel_character_component.dart';
import 'game_map.dart'; 
import 'package:easy_localization/easy_localization.dart';
import 'theme.dart';

const Map<String, Map<String, String>> comicTranslations = {
  'BOO!': {'en': 'BOO!', 'es': '¡BUU!', 'ja': 'ばあ！', 'de': 'BUH!'},
  'GOTCHA!': {'en': 'GOTCHA!', 'es': '¡TE TENGO!', 'ja': '捕まえた！', 'de': 'HAB DICH!'},
  'AAAH!': {'en': 'AAAH!', 'es': '¡AAAH!', 'ja': 'うわぁ！', 'de': 'AAAH!'},
  '*huff huff*': {'en': '*huff huff*', 'es': '*jadeo*', 'ja': '*ハァハァ*', 'de': '*keuch*'}
};

String getComicText(String key, String langCode) {
  return comicTranslations[key]?[langCode] ?? comicTranslations[key]?['en'] ?? key;
}

class PolaroidCard extends StatefulWidget {
  final ScareSnapshot snapshot;

  const PolaroidCard({super.key, required this.snapshot});

  @override
  State<PolaroidCard> createState() => _PolaroidCardState();
}

class _PolaroidCardState extends State<PolaroidCard> {
  final GlobalKey _boundaryKey = GlobalKey();
  bool _isCapturing = false;

  Future<void> _downloadImage() async {
    if (_isCapturing) return;
    setState(() => _isCapturing = true);

    try {
      // 1. Capture the widget as a pixel image
      RenderRepaintBoundary boundary = _boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0); // High res export
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      // 2. Format the filename: lumenbreach-AttackerName-169420000.png
      String safeName = widget.snapshot.attackerName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      String filename = 'lumenbreach-$safeName-${DateTime.now().millisecondsSinceEpoch}.png';

      // 3. Trigger the native save/share dialog
      await Share.shareXFiles(
        [XFile.fromData(pngBytes, name: filename, mimeType: 'image/png')],
        text: 'Got ambushed in the darkness! Can you survive Lumen Breach?\nPlay free: https://lumenbreach.com/download\n#LumenBreach #HorrorGaming',
      );

    } catch (e) {
      debugPrint('Failed to save polaroid: $e');
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  Future<void> _sendTauntToInbox() async {
    final victimId = widget.snapshot.victimId;
    if (victimId == null) return; // Only allow sending to human players
    
    if (_isCapturing) return;
    setState(() => _isCapturing = true);

    try {
      // 1. Capture the widget as a pixel image
      RenderRepaintBoundary boundary = _boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 2.0); // Slightly lower res to save bandwidth
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      final supabase = Supabase.instance.client;
      final myId = supabase.auth.currentUser!.id;
      final filename = 'taunt_${myId}_${DateTime.now().millisecondsSinceEpoch}.png';
      
      // 2. Upload to Supabase Storage
      await supabase.storage.from('inbox_attachments').uploadBinary(filename, pngBytes);
      final imageUrl = supabase.storage.from('inbox_attachments').getPublicUrl(filename);

      // 3. Create Pending Friendship (Catch error if they are already friends)
      try {
        await supabase.from('friendships').insert({
          'requester_id': myId,
          'addressee_id': victimId,
          'status': 'pending'
        });
      } catch (_) {}

      // 4. Dispatch the Translated Message
      await supabase.from('player_inbox').insert({
        'recipient_id': victimId,
        'sender_id': myId,
        'message_type': 'friend_request',
        'template_key': 'req_new_rival', // This matches your en.json key!
        'attached_image_url': imageUrl,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Taunt & Friend Request Sent!'), backgroundColor: Colors.purple),
        );
      }
    } catch (e) {
      debugPrint('Failed to send taunt: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send message.'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _downloadImage,
      child: RepaintBoundary(
        key: _boundaryKey,
        child: Container(
          width: 300,
          height: 350,
          decoration: BoxDecoration(
            color: const Color(0xFFEBEBEB), 
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10, offset: const Offset(4, 4))
            ],
          ),
          child: Column(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    margin: const EdgeInsets.all(12),
                    height: 250,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      border: Border.all(color: Colors.black87, width: 2),
                    ),
                    child: ClipRect(
                      child: GameWidget(
                        game: PhotoStudioGame(
                          snapshot: widget.snapshot,
                          // --- Safe language lookup fallback ---
                          langCode: () {
                            try {
                              return context.locale.languageCode;
                            } catch (_) {
                              return 'en'; 
                            }
                          }(), // Feed the active language here
                        ),
                      ),
                    ),
                  ),
                  if (_isCapturing)
                    const CircularProgressIndicator(color: Colors.purpleAccent),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '${widget.snapshot.attackerName} got ${widget.snapshot.victimName}!',
                            style: const TextStyle(fontFamily: 'Courier', fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text('@ ${widget.snapshot.timestamp}s', style: const TextStyle(fontFamily: 'Courier', fontSize: 12, color: Colors.black54)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Native Share/Download Button
                        IconButton(
                          icon: const Icon(Icons.share, color: Colors.black87),
                          onPressed: _downloadImage,
                          tooltip: 'Share to Socials',
                        ),
                        // In-Game Taunt Button (Only visible if the victim was a real player)
                        if (widget.snapshot.victimId != null)
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple[800]),
                            icon: const Icon(Icons.send, color: Colors.white, size: 16),
                            label: const Text('SEND TAUNT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                            onPressed: _sendTauntToInbox,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Text(
                '@ ${widget.snapshot.timestamp}s remaining',
                style: const TextStyle(fontFamily: 'Courier', fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PhotoStudioGame extends FlameGame {
  final ScareSnapshot snapshot;
  final String langCode; // Add language property

  PhotoStudioGame({required this.snapshot, this.langCode = 'en'});

  @override
  Color backgroundColor() => const Color(0xFF000000); 

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // 1. GENERATE BACKGROUND MAZE
    int seed = (snapshot.mapX.toInt() * 73856) ^ (snapshot.mapY.toInt() * 19349);
    final random = Random(seed);
    int architectureType = random.nextInt(3);

    for (int col = -1; col < 6; col++) {
      for (int row = -1; row < 4; row++) {
        bool placeWall = true;
        if (architectureType == 0 && col > 2) placeWall = false; 
        if (architectureType == 1 && (row == 0 || row == 3)) placeWall = false; 
        if (architectureType == 2 && random.nextDouble() > 0.6) placeWall = false; 
        if (row == 3) placeWall = true; 

        if (placeWall) {
          final wall = WallComponent(position: Vector2(col * 64.0, (row * 64.0) - 32.0), tileSize: 64.0);
          wall.priority = 0; 
          add(wall);
        }
      }
    }

    // 2. LIGHTING FALLOFF
    add(RectangleComponent(
      size: Vector2(400, 400),
      paint: Paint()..color = Colors.black.withOpacity(0.75),
    )..priority = 5);

    add(RectangleComponent(
      size: Vector2(400, 400),
      paint: Paint()..color = Colors.black.withOpacity(0.35),
    )..priority = 15);

    // 3. LOAD CHARACTERS
    final attackerRig = GraveStakesGame.characterRigCache[snapshot.attackerCharId] ?? GraveStakesGame.characterRigCache['default'];
    final attackerImages = GraveStakesGame.characterImagesCache[snapshot.attackerCharId] ?? GraveStakesGame.characterImagesCache['default'];
    final victimRig = GraveStakesGame.characterRigCache[snapshot.victimCharId] ?? GraveStakesGame.characterRigCache['default'];
    final victimImages = GraveStakesGame.characterImagesCache[snapshot.victimCharId] ?? GraveStakesGame.characterImagesCache['default'];

    if (attackerRig == null || victimRig == null) return;

    final attacker = VoxelCharacterComponent(images: attackerImages!, rigData: attackerRig, hitboxSize: Vector2(64, 64));
    final victim = VoxelCharacterComponent(images: victimImages!, rigData: victimRig, hitboxSize: Vector2(64, 64));

    attacker.priority = 20; 
    victim.priority = 10;   

    try {
      attacker.activeMaskImage = await images.load('${snapshot.attackerMaskId}_mask.png');
    } catch (e) {}

    int sceneLayout = snapshot.timestamp % 4;

    // --- ALL COMIC BUBBLES NOW USE getComicText AND PASS langCode ---
    switch (sceneLayout) {
      case 0: 
        attacker.scale = Vector2.all(0.9);
        attacker.position = Vector2(size.x * 0.15, size.y * 0.7);
        attacker.targetAngle = pi / 2; 
        attacker.angle = 0.2; 
        attacker.scareAnimTimer = 0.25; 

        victim.scale = Vector2.all(0.85);
        victim.position = Vector2(size.x * 0.85, size.y * 0.75);
        victim.targetAngle = pi / 2; 
        victim.angle = 0.35; 
        victim.isMoving = true; 
        victim.update(0.3); 

        add(ActionLines(position: victim.position + Vector2(-20, 0))..priority = 8);
        add(ComicBubble(text: getComicText('*huff huff*', langCode), isSpeech: false, langCode: langCode, position: victim.position + Vector2(30, 20))..priority = 12);
        add(ComicBubble(text: getComicText('BOO!', langCode), isSpeech: true, langCode: langCode, position: attacker.position + Vector2(25, -60))..priority = 25);
        break;

      case 1: 
        attacker.scale = Vector2.all(1.8); 
        attacker.position = Vector2(size.x * 0.85, size.y * 0.95);
        attacker.targetAngle = -pi / 2; 
        attacker.angle = -0.15; 
        attacker.scareAnimTimer = 0.35; 

        victim.scale = Vector2.all(0.8); 
        victim.position = Vector2(size.x * 0.25, size.y * 0.65);
        victim.targetAngle = pi / 2; 
        victim.angle = -0.25; 
        victim.isStunned = true; 
        victim.stunTimer = 999.0;

        add(ActionLines(position: attacker.position + Vector2(20, -20))..priority = 18..angle = pi);
        add(ComicBubble(text: getComicText('GOTCHA!', langCode), isSpeech: true, langCode: langCode, position: attacker.position + Vector2(-60, -100))..priority = 25);
        add(ComicBubble(text: getComicText('AAAH!', langCode), isSpeech: true, langCode: langCode, position: victim.position + Vector2(10, -60))..priority = 12);
        break;

      case 2: 
        victim.scale = Vector2.all(0.95);
        victim.position = Vector2(size.x * 0.7, size.y * 0.85);
        victim.targetAngle = -pi / 2; 
        victim.angle = -0.1; 
        victim.isStunned = true; 
        victim.stunTimer = 999.0;

        attacker.scale = Vector2.all(1.4);
        attacker.position = Vector2(size.x * 0.25, size.y * 0.25); 
        attacker.targetAngle = pi / 2; 
        attacker.angle = 0.6; 
        attacker.scareAnimTimer = 0.15; 

        add(ActionLines(position: attacker.position + Vector2(-30, -30))..priority = 18..angle = pi / 4);
        add(ComicBubble(text: getComicText('?!', langCode), isSpeech: false, langCode: langCode, position: victim.position + Vector2(20, -50))..priority = 12);
        add(ComicBubble(text: getComicText('HEHEHE', langCode), isSpeech: true, langCode: langCode, position: attacker.position + Vector2(-30, -40))..priority = 25);
        break;

      case 3: 
        attacker.scale = Vector2.all(2.6); 
        attacker.position = Vector2(size.x * 0.1, size.y * 1.1); 
        attacker.targetAngle = pi / 2; 
        attacker.angle = -0.15; 
        attacker.scareAnimTimer = 0.3;

        victim.scale = Vector2.all(0.45); 
        victim.position = Vector2(size.x * 0.85, size.y * 0.45); 
        victim.targetAngle = pi / 2; 
        victim.angle = 0.4; 
        victim.isMoving = true; 
        victim.update(0.4); 

        add(ActionLines(position: victim.position + Vector2(-15, 0))..priority = 8);
        add(ComicBubble(text: getComicText('*scuff*', langCode), isSpeech: false, langCode: langCode, position: victim.position + Vector2(20, 20))..priority = 12);
        add(ComicBubble(text: getComicText('BOO!', langCode), isSpeech: true, langCode: langCode, position: attacker.position + Vector2(40, -140))..priority = 25);
        break;
    }

    add(attacker);
    add(victim);
  }

  @override
  void update(double dt) {
    super.update(0.0);
  }
}

// ==========================================
// COMIC BOOK OVERLAY COMPONENTS
// ==========================================

class ActionLines extends PositionComponent {
  ActionLines({super.position});

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final paint = Paint()
      ..color = Colors.white54
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Draw cartoonish speed streaks stretching backward
    canvas.drawLine(const Offset(0, -10), const Offset(-50, -10), paint);
    canvas.drawLine(const Offset(10, 10), const Offset(-70, 10), paint);
    canvas.drawLine(const Offset(-5, 30), const Offset(-40, 30), paint);
  }
}

class ComicBubble extends PositionComponent {
  final String text;
  final bool isSpeech;
  final String langCode; // <-- Add language property

  ComicBubble({required this.text, required this.isSpeech, required this.langCode, super.position});

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final bgPaint = Paint()..color = isSpeech ? Colors.white : Colors.amberAccent;
    final borderPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Determine sizing based on text length
    double w = (text.length * 9.0).clamp(40.0, 100.0);
    double h = isSpeech ? 35.0 : 20.0;
    
    // Draw the main bubble shape
    final rrect = RRect.fromLTRBR(-w/2, -h/2, w/2, h/2, Radius.circular(isSpeech ? 12 : 4));
    canvas.drawRRect(rrect, bgPaint);
    canvas.drawRRect(rrect, borderPaint);

    // Draw the directional tail for speech bubbles
    if (isSpeech) {
      final path = Path()
        ..moveTo(-w/4, h/2) 
        ..lineTo(-w/2, h/2 + 15) 
        ..lineTo(0, h/2) 
        ..close();
      canvas.drawPath(path, bgPaint);
      canvas.drawPath(path, borderPaint);
    }

    // Paint the text inside using your localized dynamic font router
    final textSpan = TextSpan(
      text: text,
      style: AppTheme.getLocalizedStyle(
        langCode,
        color: Colors.black,
        fontSize: isSpeech ? 16 : 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ).copyWith(fontStyle: isSpeech ? FontStyle.normal : FontStyle.italic), // Append italic logic
    );
    
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: ui.TextDirection.ltr, // <--- Explicitly use the UI version
      textAlign: TextAlign.center,
    );
    
    textPainter.layout();
    textPainter.paint(canvas, Offset(-textPainter.width / 2, -textPainter.height / 2));
  }
}