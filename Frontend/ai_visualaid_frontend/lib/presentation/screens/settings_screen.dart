import 'package:flutter/material.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/tts_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _settingsService = SettingsService();
  final TtsService _ttsPreviewService = TtsService();

  String? _selectedOcrLanguage;
  double _ttsVolume = defaultTtsVolume;
  double _ttsPitch = defaultTtsPitch;
  double _ttsRate = defaultTtsRate;

  bool _isLoading = true;
  bool _ttsInitialized = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _ttsPreviewService.dispose();
    super.dispose();
  }


  Future<void> _loadSettings() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final loadedLang = await _settingsService.getOcrLanguage();
    final loadedVolume = await _settingsService.getTtsVolume();
    final loadedPitch = await _settingsService.getTtsPitch();
    final loadedRate = await _settingsService.getTtsRate();

    if (!_ttsInitialized) {
       await _ttsPreviewService.initTts(
         initialVolume: loadedVolume,
         initialPitch: loadedPitch,
         initialRate: loadedRate
       );
       _ttsInitialized = true;
    } else {
       await _ttsPreviewService.updateSettings(loadedVolume, loadedPitch, loadedRate);
    }

    if (mounted) {
       setState(() {
          _selectedOcrLanguage = supportedOcrLanguages.containsKey(loadedLang)
                               ? loadedLang
                               : SettingsService.getValidatedDefaultLanguage();
          _ttsVolume = loadedVolume;
          _ttsPitch = loadedPitch;
          _ttsRate = loadedRate;
          _isLoading = false;
       });
    }
  }

  Future<void> _updateOcrLanguage(String? newLanguageCode) async {
    if (newLanguageCode != null && newLanguageCode != _selectedOcrLanguage) {
      await _settingsService.setOcrLanguage(newLanguageCode);
      if(mounted) {
        setState(() {
          _selectedOcrLanguage = newLanguageCode;
        });
        _showConfirmationSnackBar('OCR Language set to ${supportedOcrLanguages[newLanguageCode] ?? newLanguageCode}');
      }
    }
  }

  Future<void> _updateTtsVolume(double newVolume) async {
    if (newVolume != _ttsVolume) {
      setState(() => _ttsVolume = newVolume);
      await _settingsService.setTtsVolume(newVolume);
      await _ttsPreviewService.updateSettings(_ttsVolume, _ttsPitch, _ttsRate);
    }
  }

  Future<void> _updateTtsPitch(double newPitch) async {
     if (newPitch != _ttsPitch) {
      setState(() => _ttsPitch = newPitch);
      await _settingsService.setTtsPitch(newPitch);
      await _ttsPreviewService.updateSettings(_ttsVolume, _ttsPitch, _ttsRate);
    }
  }

  Future<void> _updateTtsRate(double newRate) async {
     if (newRate != _ttsRate) {
       setState(() => _ttsRate = newRate);
       await _settingsService.setTtsRate(newRate);
       await _ttsPreviewService.updateSettings(_ttsVolume, _ttsPitch, _ttsRate);
     }
  }

  void _previewTts(String settingName) {
      if (_ttsInitialized) {
          _ttsPreviewService.speak("This is the new $settingName setting.");
      }
  }

   void _showConfirmationSnackBar(String message) {
     if (!mounted) return;
     ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(
         content: Text(message),
         duration: const Duration(seconds: 2),
       )
     );
   }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.teal,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: <Widget>[
                _buildOcrLanguageSetting(),
                const Divider(height: 20),
                _buildTtsSettingsHeader(),
                _buildTtsVolumeSetting(),
                _buildTtsPitchSetting(),
                _buildTtsRateSetting(),
                const Divider(height: 30),
                 _buildAboutSection(),
              ],
            ),
    );
  }

  Widget _buildOcrLanguageSetting() {
    return ListTile(
      leading: const Icon(Icons.translate),
      title: const Text('Text Recognition Language'),
      subtitle: Text('Select the primary language for OCR (${supportedOcrLanguages[_selectedOcrLanguage] ?? _selectedOcrLanguage})'),
      trailing: DropdownButton<String>(
        value: _selectedOcrLanguage,
        onChanged: _selectedOcrLanguage == null ? null : _updateOcrLanguage,
        items: supportedOcrLanguages.entries.map((entry) {
          return DropdownMenuItem<String>(
            value: entry.key,
            child: Text(entry.value),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTtsSettingsHeader() {
     return const ListTile(
         leading: Icon(Icons.volume_up),
         title: Text('Text-to-Speech Settings'),
         subtitle: Text('Adjust voice characteristics'),
     );
  }

  Widget _buildTtsVolumeSetting() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
           Text('Volume: ${_ttsVolume.toStringAsFixed(1)}'),
           Slider(
            value: _ttsVolume,
            onChanged: (newVolume) {
               setState(() => _ttsVolume = newVolume);
               _ttsPreviewService.updateSettings(_ttsVolume, _ttsPitch, _ttsRate);
            },
            onChangeEnd: (newVolume) {
              _updateTtsVolume(newVolume);
              _previewTts("volume");
            },
            min: 0.0,
            max: 1.0,
            divisions: 10,
            label: "Volume: ${_ttsVolume.toStringAsFixed(1)}",
          ),
        ],
      ),
    );
  }

    Widget _buildTtsPitchSetting() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
           Text('Pitch: ${_ttsPitch.toStringAsFixed(1)}'),
           Slider(
            value: _ttsPitch,
            onChanged: (newPitch) {
               setState(() => _ttsPitch = newPitch);
               _ttsPreviewService.updateSettings(_ttsVolume, _ttsPitch, _ttsRate);
            },
             onChangeEnd: (newPitch) {
              _updateTtsPitch(newPitch);
               _previewTts("pitch");
            },
            min: 0.5,
            max: 2.0,
            divisions: 15,
            label: "Pitch: ${_ttsPitch.toStringAsFixed(1)}",
            activeColor: Colors.red,
          ),
        ],
      ),
    );
  }

  Widget _buildTtsRateSetting() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
           Text('Speed: ${_ttsRate.toStringAsFixed(1)}'),
           Slider(
            value: _ttsRate,
            onChanged: (newRate) {
               setState(() => _ttsRate = newRate);
               _ttsPreviewService.updateSettings(_ttsVolume, _ttsPitch, _ttsRate);
            },
            onChangeEnd: (newRate) {
              _updateTtsRate(newRate);
              _previewTts("speed");
            },
            min: 0.0,
            max: 1.0,
            divisions: 10,
            label: "Speed: ${_ttsRate.toStringAsFixed(1)}",
            activeColor: Colors.green,
          ),
        ],
      ),
    );
  }

  Widget _buildAboutSection() {
      return ListTile(
      leading: const Icon(Icons.info_outline),
      title: const Text('About'),
       subtitle: const Text('Version, Licenses, etc.'),
       onTap: () {
          showAboutDialog(
             context: context,
             applicationName: 'VisionAid Companion',
             applicationVersion: '1.0.1+tts',
             applicationIcon: const Icon(Icons.visibility),
             children: [
                const Padding(
                  padding: EdgeInsets.only(top: 15),
                  child: Text('Assistive technology application with TTS.'),
                )
             ]
          );
       },
    );
  }
}