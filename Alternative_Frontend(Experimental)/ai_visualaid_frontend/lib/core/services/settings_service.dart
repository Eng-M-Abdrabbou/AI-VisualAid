// lib/core/services/settings_service.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart'; 

const Map<String, String> supportedOcrLanguages = {
  'en': 'English',
  'ar': 'Arabic',
  'fa': 'Persian (Farsi)',
  'ur': 'Urdu',
  'ug': 'Uyghur',
  'hi': 'Hindi',
  'mr': 'Marathi',
  'ne': 'Nepali',
  'ru': 'Russian',
  'ch_sim': 'Chinese (Simplified)',
  'ch_tra': 'Chinese (Traditional)',
  'ja': 'Japanese',
  'ko': 'Korean',
  'te': 'Telugu',
  'kn': 'Kannada',
  'bn': 'Bengali',
}; 

const String defaultOcrLanguage = 'en';

class SettingsService {
  static const String _ocrLanguageKey = 'ocr_language';

  static String getValidatedDefaultLanguage() {
    return supportedOcrLanguages.containsKey(defaultOcrLanguage)
        ? defaultOcrLanguage
        : supportedOcrLanguages.keys.first;
  }

  Future<SharedPreferences> _getPrefs() async {
    return await SharedPreferences.getInstance();
  }

  Future<String> getOcrLanguage() async {
    try {
      final prefs = await _getPrefs();
      final savedLang = prefs.getString(_ocrLanguageKey);
      if (savedLang != null && supportedOcrLanguages.containsKey(savedLang)) {
        debugPrint('[SettingsService] Loaded OCR Language: $savedLang');
        return savedLang;
      } else {
        final defaultLang = getValidatedDefaultLanguage();
        debugPrint('[SettingsService] No valid language saved/found, returning default: $defaultLang');
        await prefs.setString(_ocrLanguageKey, defaultLang);
        return defaultLang;
      }
    } catch (e) {
      debugPrint('[SettingsService] Error loading OCR language: $e. Returning default.');
      return getValidatedDefaultLanguage();
    }
  }

  Future<void> setOcrLanguage(String languageCode) async {
    if (!supportedOcrLanguages.containsKey(languageCode)) {
       debugPrint('[SettingsService] Attempted to save unsupported language: $languageCode');
       return;
    }
    try {
      final prefs = await _getPrefs();
      await prefs.setString(_ocrLanguageKey, languageCode);
      debugPrint('[SettingsService] Saved OCR Language: $languageCode');
    } catch (e) {
      debugPrint('[SettingsService] Error saving OCR language: $e');
    }
  }
}