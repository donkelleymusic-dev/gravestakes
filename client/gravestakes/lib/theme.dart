import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Global font router to prevent "Tofu Blocks" on localized text
  static TextStyle getLocalizedStyle(
    String langCode, {
    double fontSize = 16,
    Color color = Colors.white,
    FontWeight fontWeight = FontWeight.normal,
    double? letterSpacing,
    List<Shadow>? shadows,
  }) {
    switch (langCode) {
      case 'ja': 
        return GoogleFonts.notoSansJp(fontSize: fontSize, color: color, fontWeight: fontWeight, letterSpacing: letterSpacing, shadows: shadows);
      case 'ko': 
        return GoogleFonts.notoSansKr(fontSize: fontSize, color: color, fontWeight: fontWeight, letterSpacing: letterSpacing, shadows: shadows);
      case 'zh-Hans': 
        return GoogleFonts.notoSansSc(fontSize: fontSize, color: color, fontWeight: fontWeight, letterSpacing: letterSpacing, shadows: shadows);
      case 'ru': 
        return GoogleFonts.rubik(fontSize: fontSize, color: color, fontWeight: fontWeight, letterSpacing: letterSpacing, shadows: shadows);
      case 'hi': 
        return GoogleFonts.notoSansDevanagari(fontSize: fontSize, color: color, fontWeight: fontWeight, letterSpacing: letterSpacing, shadows: shadows);
      case 'fa': 
      case 'ar': 
        return GoogleFonts.notoSansArabic(fontSize: fontSize, color: color, fontWeight: fontWeight, letterSpacing: letterSpacing, shadows: shadows);
      default: 
        // Your default horror aesthetic for Latin/English text
        return TextStyle(fontFamily: 'Courier', fontSize: fontSize, color: color, fontWeight: fontWeight, letterSpacing: letterSpacing, shadows: shadows);
    }
  }
}