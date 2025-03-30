// lib/presentation/screens/settings_screen.dart
import 'package:flutter/material.dart';
import '../../core/services/settings_service.dart'; 

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _settingsService = SettingsService();
  String? _selectedOcrLanguage; 
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    final loadedLang = await _settingsService.getOcrLanguage();
    if (mounted) {
       setState(() {
          _selectedOcrLanguage = supportedOcrLanguages.containsKey(loadedLang)
                               ? loadedLang
                               : SettingsService.getValidatedDefaultLanguage();
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
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(
             content: Text('OCR Language set to ${supportedOcrLanguages[newLanguageCode] ?? newLanguageCode}'),
             duration: const Duration(seconds: 2),
           )
        );
      }
    }
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
                const Divider(height: 30), 
                 ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('About'),
                   subtitle: const Text('Version, Licenses, etc.'),
                   onTap: () {
                      showAboutDialog(
                         context: context,
                         applicationName: 'VisionAid Companion',
                         applicationVersion: '1.0.0', 
                         applicationIcon: const Icon(Icons.visibility),
                         children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 15),
                              child: Text('Assistive technology application.'),
                            )
                         ]
                      );
                   },
                ),
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
}