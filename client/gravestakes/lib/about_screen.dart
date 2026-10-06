import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart'; // NEW: Required for opening browser links

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

  // --- NEW: URL Launcher Helper ---
  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $urlString');
    }
  }

  // --- NEW: Reusable Button Builder ---
  Widget _buildLinkButton({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        side: BorderSide(color: color.withOpacity(0.5), width: 2),
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      icon: Icon(icon, color: color),
      label: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
      onPressed: onTap,
    );
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
                crossAxisAlignment: CrossAxisAlignment.stretch, // Changed to stretch so buttons fill the width
                children: [
                  // ==========================================
                  // 1. APP STORE COMPLIANCE LINKS (STATIC)
                  // ==========================================
                  _buildLinkButton(
                    icon: Icons.privacy_tip,
                    label: 'PRIVACY POLICY',
                    color: Colors.cyanAccent,
                    onTap: () => _launchURL('http://lumenbreach.com/privacypolicy_lumenbreach.html'), // Update to actual URL
                  ),
                  const SizedBox(height: 16),
                  
                  _buildLinkButton(
                    icon: Icons.gavel,
                    label: 'TERMS OF SERVICE',
                    color: Colors.orangeAccent,
                    onTap: () => _launchURL('http://lumenbreach.com/termsandconditions_lumenbreach.html'), // Update to actual URL
                  ),
                  const SizedBox(height: 16),

                  _buildLinkButton(
                    icon: Icons.help_outline,
                    label: 'SUPPORT & ACCOUNT DELETION',
                    color: Colors.redAccent,
                    onTap: () => _launchURL('https://lumenbreach.com/support.php'), // Update to actual URL
                  ),
                  
                  const SizedBox(height: 40),
                  const Divider(color: Colors.white24),
                  const SizedBox(height: 30),

                  // ==========================================
                  // 2. DYNAMIC DATABASE CREDITS (DYNAMIC)
                  // ==========================================
                  ..._sections.map((section) {
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
                            body.replaceAll('\\n', '\n'), 
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
                  }),
                ],
              ),
            ),
    );
  }
}