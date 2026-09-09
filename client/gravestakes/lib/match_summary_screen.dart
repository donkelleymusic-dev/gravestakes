import 'package:flutter/material.dart';
import 'polaroid_card.dart'; // Assuming this is where you saved the PolaroidCard
import 'game.dart'; // To access the ScareSnapshot model

class MatchSummaryScreen extends StatelessWidget {
  final List<ScareSnapshot> photos;

  const MatchSummaryScreen({super.key, required this.photos});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        title: const Text('MATCH SUMMARY', style: TextStyle(color: Colors.purpleAccent, letterSpacing: 2.0)),
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(), // Return to menu/crypt
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: Text(
              'HIGHLIGHT REEL', 
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1.5)
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Swipe to view the horrors inflicted this match.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
          
          Expanded(
            child: photos.isEmpty
                ? const Center(
                    child: Text('No scares recorded. Cowards.', style: TextStyle(color: Colors.white38, fontStyle: FontStyle.italic)),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
                    itemCount: photos.length,
                    separatorBuilder: (context, index) => const SizedBox(width: 24),
                    itemBuilder: (context, index) {
                      // Center the polaroid vertically within the scrolling row
                      return Center(child: PolaroidCard(snapshot: photos[index]));
                    },
                  ),
          ),
          
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.black54,
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple[800],
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: () {
                // Typically you'd route back to your Main Menu or Crypt here
                Navigator.of(context).pop(); 
              },
              child: const Text('RETURN TO SHADOWS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            ),
          ),
        ],
      ),
    );
  }
}