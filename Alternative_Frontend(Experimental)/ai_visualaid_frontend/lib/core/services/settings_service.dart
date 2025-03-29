// lib/core/services/settings_service.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart'; // For debugPrint

// Define supported languages (match codes with backend easyocr codes)
const Map<String, String> supportedOcrLanguages = {
  'en': 'English',
  'es': 'Spanish',
  'fr': 'French',
  // Add more languages here (e.g., 'de': 'German')
  // Ensure these codes are supported by easyocr and initialized in the backend
};

// Default language if none is set
const String defaultOcrLanguage = 'en';

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
        debugPrint('[SettingsService] No valid language saved, returning default: $defaultLang');
        return defaultLang; // Return default if not set or invalid
      }
    } catch (e) {
      debugPrint('[SettingsService] Error loading OCR language: $e. Returning default.');
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

  // --- Add other settings methods here later (e.g., object detection confidence) ---

}