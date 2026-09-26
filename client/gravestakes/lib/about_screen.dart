import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  List<Map<String, dynamic>> _sections = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchCredits();
  }

  Future<void> _fetchCredits() async {
    try {
      final res = await Supabase.instance.client
          .from('app_credits')
          .select()
          .order('display_order', ascending: true);

      setState(() {
        _sections = List<Map<String, dynamic>>.from(res);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching credits: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        title: const Text('ABOUT & CREDITS', style: TextStyle(letterSpacing: 2.0, color: Colors.purpleAccent, fontSize: 16)),
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.purpleAccent))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _sections.map((section) {
                  final title = section['section_title'] as String? ?? '';
                  final body = section['body_text'] as String? ?? '';
                  
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 28.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (title.isNotEmpty) ...[
                          Text(
                            title.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                              fontFamily: 'Courier',
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        Text(
                          body.replaceAll('\\n', '\n'), // Safely parse line breaks from database strings
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            height: 1.6,
                            fontFamily: 'Courier',
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
    );
  }
}