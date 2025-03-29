// lib/core/services/settings_service.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart'; // For debugPrint

// Define supported languages (match codes with backend easyocr codes)
// Map<LanguageCode, DisplayName>
const Map<String, String> supportedOcrLanguages = {
  // Latin Basic + European Extensions
  'en': 'English',
  // Arabic Script
  'ar': 'Arabic',
  'fa': 'Persian (Farsi)',
  'ur': 'Urdu',
  'ug': 'Uyghur',
  // Devanagari Script (and related)
  'hi': 'Hindi',
  'mr': 'Marathi',
  'ne': 'Nepali',
  // Cyrillic Script
  'ru': 'Russian',
  // Use easyocr specific code
  // East Asian
  'ch_sim': 'Chinese (Simplified)', // Use easyocr specific code
  'ch_tra': 'Chinese (Traditional)', // Use easyocr specific code
  'ja': 'Japanese',
  'ko': 'Korean',
  // South Indic Scripts
  'te': 'Telugu',
  'kn': 'Kannada',
  // East Indic Scripts
  'bn': 'Bengali',
  // Add other languages supported by easyocr if needed
  // Check easyocr documentation for the latest list and codes
};

// Default language if none is set
const String defaultOcrLanguage = 'en'; // English remains default

class SettingsService {
  static const String _ocrLanguageKey = 'ocr_language';

  // Ensure the default language code is valid
  static String getValidatedDefaultLanguage() {
    return supportedOcrLanguages.containsKey(defaultOcrLanguage)
        ? defaultOcrLanguage
        : supportedOcrLanguages.keys.first; // Fallback to the first supported lang
  }

  Future<SharedPreferences> _getPrefs() async {
    return await SharedPreferences.getInstance();
  }

  // --- OCR Language ---

  Future<String> getOcrLanguage() async {
    try {
      final prefs = await _getPrefs();
      final savedLang = prefs.getString(_ocrLanguageKey);
      // Validate saved language against supported list
      if (savedLang != null && supportedOcrLanguages.containsKey(savedLang)) {
        debugPrint('[SettingsService] Loaded OCR Language: $savedLang');
        return savedLang;
      } else {
        final defaultLang = getValidatedDefaultLanguage();
        debugPrint('[SettingsService] No valid language saved/found, returning default: $defaultLang');
        await prefs.setString(_ocrLanguageKey, defaultLang); // Save the default if invalid was loaded
        return defaultLang;
      }
    } catch (e) {
      debugPrint('[SettingsService] Error loading OCR language: $e. Returning default.');
      // Attempt to save default on error as well? Maybe not necessary.
      return getValidatedDefaultLanguage();
    }
  }

  Future<void> setOcrLanguage(String languageCode) async {
    if (!supportedOcrLanguages.containsKey(languageCode)) {
       debugPrint('[SettingsService] Attempted to save unsupported language: $languageCode');
       return; // Don't save unsupported languages
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