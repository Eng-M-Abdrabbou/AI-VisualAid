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

const double defaultTtsVolume = 0.8;
const double defaultTtsPitch = 1.0;
const double defaultTtsRate = 0.5;

class SettingsService {
  static const String _ocrLanguageKey = 'ocr_language';
  static const String _ttsVolumeKey = 'tts_volume';
  static const String _ttsPitchKey = 'tts_pitch';
  static const String _ttsRateKey = 'tts_rate';

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

  Future<double> getTtsVolume() async {
    try {
      final prefs = await _getPrefs();
      final volume = prefs.getDouble(_ttsVolumeKey);
      if (volume != null && volume >= 0.0 && volume <= 1.0) {
        debugPrint('[SettingsService] Loaded TTS Volume: $volume');
        return volume;
      } else {
         debugPrint('[SettingsService] Invalid/No TTS Volume found, returning default: $defaultTtsVolume');
         await prefs.setDouble(_ttsVolumeKey, defaultTtsVolume);
         return defaultTtsVolume;
      }
    } catch (e) {
       debugPrint('[SettingsService] Error loading TTS Volume: $e. Returning default.');
       return defaultTtsVolume;
    }
  }

  Future<void> setTtsVolume(double volume) async {
    try {
      final prefs = await _getPrefs();
      await prefs.setDouble(_ttsVolumeKey, volume.clamp(0.0, 1.0));
      debugPrint('[SettingsService] Saved TTS Volume: $volume');
    } catch (e) {
      debugPrint('[SettingsService] Error saving TTS Volume: $e');
    }
  }

  Future<double> getTtsPitch() async {
    try {
       final prefs = await _getPrefs();
       final pitch = prefs.getDouble(_ttsPitchKey);
       if (pitch != null && pitch >= 0.5 && pitch <= 2.0) {
         debugPrint('[SettingsService] Loaded TTS Pitch: $pitch');
         return pitch;
       } else {
         debugPrint('[SettingsService] Invalid/No TTS Pitch found, returning default: $defaultTtsPitch');
         await prefs.setDouble(_ttsPitchKey, defaultTtsPitch);
         return defaultTtsPitch;
       }
    } catch (e) {
       debugPrint('[SettingsService] Error loading TTS Pitch: $e. Returning default.');
       return defaultTtsPitch;
    }
  }

  Future<void> setTtsPitch(double pitch) async {
    try {
      final prefs = await _getPrefs();
      await prefs.setDouble(_ttsPitchKey, pitch.clamp(0.5, 2.0));
      debugPrint('[SettingsService] Saved TTS Pitch: $pitch');
    } catch (e) {
      debugPrint('[SettingsService] Error saving TTS Pitch: $e');
    }
  }

  Future<double> getTtsRate() async {
    try {
       final prefs = await _getPrefs();
       final rate = prefs.getDouble(_ttsRateKey);
        if (rate != null && rate >= 0.0 && rate <= 1.0) {
         debugPrint('[SettingsService] Loaded TTS Rate: $rate');
         return rate;
       } else {
         debugPrint('[SettingsService] Invalid/No TTS Rate found, returning default: $defaultTtsRate');
         await prefs.setDouble(_ttsRateKey, defaultTtsRate);
         return defaultTtsRate;
       }
    } catch (e) {
       debugPrint('[SettingsService] Error loading TTS Rate: $e. Returning default.');
       return defaultTtsRate;
    }
  }

  Future<void> setTtsRate(double rate) async {
    try {
      final prefs = await _getPrefs();
      await prefs.setDouble(_ttsRateKey, rate.clamp(0.0, 1.0));
      debugPrint('[SettingsService] Saved TTS Rate: $rate');
    } catch (e) {
      debugPrint('[SettingsService] Error saving TTS Rate: $e');
    }
  }
}