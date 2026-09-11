import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LanguageSelector extends StatelessWidget {
  const LanguageSelector({super.key});

  final Map<String, String> supportedLanguages = const {
    'en': 'English', 'es': 'Español', 'pt-BR': 'Português (BR)',
    'ja': '日本語', 'ko': '한국어', 'de': 'Deutsch', 'fr': 'Français', 
    'ru': 'Русский', 'hi': 'हिन्दी', 'fa': 'فارسی', 'ar': 'العربية'
  };

  Future<void> _updateLanguage(BuildContext context, String langCode) async {
    // Safely parse regional locales (e.g., pt-BR becomes Locale('pt', 'BR'))
    Locale targetLocale;
    if (langCode.contains('-')) {
      final parts = langCode.split('-');
      targetLocale = Locale(parts[0], parts[1]);
    } else {
      targetLocale = Locale(langCode);
    }
    
    // Switch the local UI
    await context.setLocale(targetLocale);
    
    // Sync to Supabase
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        await Supabase.instance.client.from('profiles').update({'language_code': langCode}).eq('id', user.id);
      } catch (e) {
        debugPrint('Failed to sync language to DB: $e');
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    String currentLang = context.locale.languageCode;
    if (context.locale.countryCode != null) currentLang = '${context.locale.languageCode}-${context.locale.countryCode}';
    if (!supportedLanguages.containsKey(currentLang)) currentLang = 'en';

    return DropdownButton<String>(
      value: currentLang,
      dropdownColor: Colors.black87,
      style: const TextStyle(color: Colors.white, fontFamily: 'Courier'),
      underline: Container(height: 2, color: Colors.purpleAccent),
      icon: const Icon(Icons.language, color: Colors.purpleAccent),
      items: supportedLanguages.entries.map((entry) => DropdownMenuItem<String>(
        value: entry.key,
        child: Text(entry.value),
      )).toList(),
      onChanged: (newLang) { if (newLang != null) _updateLanguage(context, newLang); },
    );
  }
}