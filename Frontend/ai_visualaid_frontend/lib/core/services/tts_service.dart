import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/material.dart';

enum TtsState { playing, stopped, paused, continued }

class TtsService {
  late FlutterTts flutterTts;
  double volume = 0.8;
  double pitch = 1.0;
  double rate = 0.5;

  TtsState ttsState = TtsState.stopped;

  bool get isPlaying => ttsState == TtsState.playing;
  bool get isStopped => ttsState == TtsState.stopped;
  bool get isPaused => ttsState == TtsState.paused;
  bool get isContinued => ttsState == TtsState.continued;

  bool get isIOS => !kIsWeb && Platform.isIOS;
  bool get isAndroid => !kIsWeb && Platform.isAndroid;

  Future<void> initTts({
    double initialVolume = 0.8,
    double initialPitch = 1.0,
    double initialRate = 0.5,
  }) async {
    volume = initialVolume.clamp(0.0, 1.0);
    pitch = initialPitch.clamp(0.5, 2.0);
    rate = initialRate.clamp(0.0, 1.0);

    flutterTts = FlutterTts();

    await _setAwaitOptions();

    flutterTts.setStartHandler(() {
      debugPrint("[TtsService] Playing");
      ttsState = TtsState.playing;
    });

    flutterTts.setCompletionHandler(() {
      debugPrint("[TtsService] Complete");
      ttsState = TtsState.stopped;
    });

    flutterTts.setCancelHandler(() {
      debugPrint("[TtsService] Cancel");
      ttsState = TtsState.stopped;
    });

    flutterTts.setPauseHandler(() {
      debugPrint("[TtsService] Paused");
      ttsState = TtsState.paused;
    });

    flutterTts.setContinueHandler(() {
      debugPrint("[TtsService] Continued");
      ttsState = TtsState.continued;
    });

    flutterTts.setErrorHandler((msg) {
      debugPrint("[TtsService] error: $msg");
      ttsState = TtsState.stopped;
    });

    await applySettings();
    debugPrint("[TtsService] TTS Initialized with V:$volume, P:$pitch, R:$rate");
  }

  Future<void> applySettings() async {
     try {
        await flutterTts.setVolume(volume);
        await flutterTts.setSpeechRate(rate);
        await flutterTts.setPitch(pitch);
     } catch (e) {
        debugPrint("[TtsService] Error applying settings: $e");
     }
  }


  Future<void> updateSettings(double newVolume, double newPitch, double newRate) async {
    volume = newVolume.clamp(0.0, 1.0);
    pitch = newPitch.clamp(0.5, 2.0);
    rate = newRate.clamp(0.0, 1.0);
    await applySettings();
    debugPrint("[TtsService] Settings Updated V:$volume, P:$pitch, R:$rate");
  }

  Future<void> speak(String text) async {
    if (text.isNotEmpty && ttsState != TtsState.playing) {
       await applySettings();
       await flutterTts.speak(text);
    } else if (ttsState == TtsState.playing) {
        await stop();
        await Future.delayed(const Duration(milliseconds: 100));
        if (text.isNotEmpty) {
           await applySettings();
           await flutterTts.speak(text);
        }
    }
  }

  Future<void> _setAwaitOptions() async {
    await flutterTts.awaitSpeakCompletion(true);
  }

  Future<void> stop() async {
    var result = await flutterTts.stop();
    if (result == 1) ttsState = TtsState.stopped;
  }


  Future<void> dispose() async {
    await stop();
  }
}