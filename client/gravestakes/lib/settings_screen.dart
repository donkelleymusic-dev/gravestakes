import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'language_selector.dart';
import 'theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Grab the active language code to ensure the titles render correctly
    String currentLang = context.locale.languageCode;

    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        title: Text(
          'SETTINGS', 
          style: AppTheme.getLocalizedStyle(currentLang, color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2.0)
        ),
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'PREFERENCES', 
            style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)
          ),
          const SizedBox(height: 12),
          
          // Language Toggle
          ListTile(
            tileColor: Colors.black54,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8), 
              side: const BorderSide(color: Colors.white24)
            ),
            leading: const Icon(Icons.language, color: Colors.purpleAccent),
            title: Text(
              'Language / Idioma', 
              style: AppTheme.getLocalizedStyle(currentLang, color: Colors.white, fontWeight: FontWeight.bold)
            ),
            trailing: const LanguageSelector(),
          ),
          
          const SizedBox(height: 32),
          const Text(
            'ACCOUNT', 
            style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)
          ),
          const SizedBox(height: 12),
          
          // Future expansion for Audio/Account controls
          ListTile(
            tileColor: Colors.black54,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8), 
              side: const BorderSide(color: Colors.redAccent)
            ),
            leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
            title: Text(
              'Delete Account', 
              style: AppTheme.getLocalizedStyle(currentLang, color: Colors.redAccent)
            ),
            onTap: () {
              // Add account deletion warning dialog logic here later
            },
          ),
        ],
      ),
    );
  }
}