import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';


const Map<String, String> supportedOcrLanguages = {
  'eng': 'English',
  'ara': 'Arabic',
  'fas': 'Persian (Farsi)',
  'urd': 'Urdu',
  'uig': 'Uyghur',
  'hin': 'Hindi',
  'mar': 'Marathi',
  'nep': 'Nepali',
  'rus': 'Russian',
  'chi_sim': 'Chinese (Simplified)',
  'chi_tra': 'Chinese (Traditional)',
  'jpn': 'Japanese',
  'kor': 'Korean',
  'tel': 'Telugu',
  'kan': 'Kannada',
  'ben': 'Bengali',

};

const String defaultOcrLanguage = 'eng';


const double defaultTtsVolume = 0.8;
const double defaultTtsPitch = 1.0;
const double defaultTtsRate = 0.5;


const String defaultObjectCategory = 'all';


const Map<String, String> objectDetectionCategories = {
  'all': 'All Objects',
  'people': 'People',
  'vehicles': 'Vehicles',
  'furniture': 'Furniture & Appliances',
  'animals': 'Animals',
  'accessories': 'Accessories',
  'sports': 'Sports Equipment',
  'kitchen': 'Kitchen & Food',
  'electronics': 'Electronics',
  'outdoor': 'Outdoor Fixtures',
  'indoor': 'Indoor Items',
};

// Mapping from COCO object names (lowercase) to category keys
const Map<String, String> cocoObjectToCategoryMap = {
  // People
  'person': 'people',
  // Vehicles
  'bicycle': 'vehicles',
  'car': 'vehicles',
  'motorcycle': 'vehicles',
  'airplane': 'vehicles',
  'bus': 'vehicles',
  'train': 'vehicles',
  'truck': 'vehicles',
  'boat': 'vehicles',
  // Outdoor Fixtures
  'traffic light': 'outdoor',
  'fire hydrant': 'outdoor',
  'stop sign': 'outdoor',
  'parking meter': 'outdoor',
  'bench': 'outdoor',
  // Animals
  'bird': 'animals',
  'cat': 'animals',
  'dog': 'animals',
  'horse': 'animals',
  'sheep': 'animals',
  'cow': 'animals',
  'elephant': 'animals',
  'bear': 'animals',
  'zebra': 'animals',
  'giraffe': 'animals',
  // Accessories
  'backpack': 'accessories',
  'umbrella': 'accessories',
  'handbag': 'accessories',
  'tie': 'accessories',
  'suitcase': 'accessories',
  // Sports
  'frisbee': 'sports',
  'skis': 'sports',
  'snowboard': 'sports',
  'sports ball': 'sports',
  'kite': 'sports',
  'baseball bat': 'sports',
  'baseball glove': 'sports',
  'skateboard': 'sports',
  'surfboard': 'sports',
  'tennis racket': 'sports',
  // Kitchen & Food
  'bottle': 'kitchen',
  'wine glass': 'kitchen',
  'cup': 'kitchen',
  'fork': 'kitchen',
  'knife': 'kitchen',
  'spoon': 'kitchen',
  'bowl': 'kitchen',
  'banana': 'kitchen',
  'apple': 'kitchen',
  'sandwich': 'kitchen',
  'orange': 'kitchen',
  'broccoli': 'kitchen',
  'carrot': 'kitchen',
  'hot dog': 'kitchen',
  'pizza': 'kitchen',
  'donut': 'kitchen',
  'cake': 'kitchen',
  'sink': 'kitchen', // Often in kitchen
  // Furniture & Appliances
  'chair': 'furniture',
  'couch': 'furniture',
  'bed': 'furniture',
  'dining table': 'furniture',
  'refrigerator': 'furniture', // Appliance grouped
  'oven': 'furniture', // Appliance grouped
  'toaster': 'furniture', // Appliance grouped
  'microwave': 'furniture', // Appliance grouped
   'toilet': 'indoor', // Moved to indoor
  // Electronics
  'tv': 'electronics',
  'laptop': 'electronics',
  'mouse': 'electronics',
  'remote': 'electronics',
  'keyboard': 'electronics',
  'cell phone': 'electronics',
  // Indoor Misc
  'book': 'indoor',
  'clock': 'indoor',
  'vase': 'indoor',
  'scissors': 'indoor',
  'teddy bear': 'indoor',
  'hair drier': 'furniture', // Grouped with appliances
  'toothbrush': 'indoor',
  'potted plant': 'indoor', // Often indoor
};


class SettingsService {
  static const String _ocrLanguageKey = 'ocr_language';
  static const String _ttsVolumeKey = 'tts_volume';
  static const String _ttsPitchKey = 'tts_pitch';
  static const String _ttsRateKey = 'tts_rate';
  static const String _objectCategoryKey = 'object_category'; // New key


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


  Future<String> getObjectDetectionCategory() async {
      try {
        final prefs = await _getPrefs();
        final savedCategory = prefs.getString(_objectCategoryKey);
        if (savedCategory != null && objectDetectionCategories.containsKey(savedCategory)) {
          debugPrint('[SettingsService] Loaded Object Category: $savedCategory');
          return savedCategory;
        } else {
           debugPrint('[SettingsService] Invalid/No Object Category found, returning default: $defaultObjectCategory');
           await prefs.setString(_objectCategoryKey, defaultObjectCategory);
           return defaultObjectCategory;
        }
      } catch (e) {
        debugPrint('[SettingsService] Error loading Object Category: $e. Returning default.');
        return defaultObjectCategory;
      }
  }

  Future<void> setObjectDetectionCategory(String categoryKey) async {
      if (!objectDetectionCategories.containsKey(categoryKey)) {
          debugPrint('[SettingsService] Attempted to save unsupported object category: $categoryKey');
          return;
      }
      try {
        final prefs = await _getPrefs();
        await prefs.setString(_objectCategoryKey, categoryKey);
        debugPrint('[SettingsService] Saved Object Category: $categoryKey');
      } catch (e) {
        debugPrint('[SettingsService] Error saving Object Category: $e');
      }
  }

}