import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Sound Service for playing audio notifications in KDS
///
/// Plays sounds when:
/// - New order arrives
/// - Order becomes ready
/// - Urgent/long waiting orders
class SoundService {
  static final SoundService _instance = SoundService._internal();
  factory SoundService() => _instance;
  SoundService._internal();

  AudioPlayer? _audioPlayer;
  bool _isInitialized = false;
  bool _isMuted = false;
  bool _hasAudioFiles = false;

  bool get isInitialized => _isInitialized;
  bool get isMuted => _isMuted;

  /// Initialize the sound service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _audioPlayer = AudioPlayer();

      // Try to set audio context for Android
      try {
        await _audioPlayer!.setAudioContext(
          AudioContext(
            android: AudioContextAndroid(
              isSpeakerphoneOn: true,
              stayAwake: true,
              contentType: AndroidContentType.sonification,
              usageType: AndroidUsageType.notification,
              audioFocus: AndroidAudioFocus.gain,
            ),
          ),
        );
      } catch (e) {
        debugPrint('⚠️ Could not set audio context: $e');
      }

      // Check if audio files exist
      try {
        await _audioPlayer!.setSource(AssetSource('sounds/beep.mp3'));
        _hasAudioFiles = true;
        debugPrint('✅ Audio files found');
      } catch (e) {
        _hasAudioFiles = false;
        debugPrint('⚠️ No audio files found, using fallback sounds');
      }

      _isInitialized = true;
      debugPrint('✅ SoundService initialized');
    } catch (e) {
      debugPrint('❌ Error initializing SoundService: $e');
      _isInitialized = false;
    }
  }

  /// Play new order notification sound
  Future<void> playNewOrderSound() async {
    if (!_isInitialized || _isMuted) {
      _playSystemSound();
      return;
    }

    try {
      if (_hasAudioFiles) {
        await _audioPlayer!.play(AssetSource('sounds/new_order.mp3'));
      } else {
        _playSystemSound();
      }
      debugPrint('🔊 New order sound played');
    } catch (e) {
      debugPrint('⚠️ Using fallback sound for new order');
      _playSystemSound();
    }
  }

  /// Play order ready notification sound
  Future<void> playOrderReadySound() async {
    if (!_isInitialized || _isMuted) {
      _playSystemSound();
      return;
    }

    try {
      if (_hasAudioFiles) {
        await _audioPlayer!.play(AssetSource('sounds/order_ready.mp3'));
      } else {
        _playSystemSound();
      }
      debugPrint('🔊 Order ready sound played');
    } catch (e) {
      _playSystemSound();
    }
  }

  /// Play urgent notification sound
  Future<void> playUrgentSound() async {
    if (!_isInitialized || _isMuted) {
      _playSystemSound();
      return;
    }

    try {
      if (_hasAudioFiles) {
        await _audioPlayer!.play(AssetSource('sounds/urgent.mp3'));
      } else {
        // Play system sound twice for urgency
        _playSystemSound();
        await Future.delayed(const Duration(milliseconds: 200));
        _playSystemSound();
      }
      debugPrint('🔊 Urgent sound played');
    } catch (e) {
      _playSystemSound();
    }
  }

  /// Play success sound
  Future<void> playSuccessSound() async {
    if (!_isInitialized || _isMuted) return;

    try {
      if (_hasAudioFiles) {
        await _audioPlayer!.play(AssetSource('sounds/success.mp3'));
      }
      debugPrint('🔊 Success sound played');
    } catch (e) {
      // Silent for success
    }
  }

  /// Play error sound
  Future<void> playErrorSound() async {
    if (!_isInitialized || _isMuted) return;

    try {
      if (_hasAudioFiles) {
        await _audioPlayer!.play(AssetSource('sounds/error.mp3'));
      } else {
        _playSystemSound();
      }
      debugPrint('🔊 Error sound played');
    } catch (e) {
      _playSystemSound();
    }
  }

  /// Play test sound
  Future<void> playTestSound() async {
    if (!_isInitialized) return;

    try {
      if (_hasAudioFiles) {
        await _audioPlayer!.play(AssetSource('sounds/test.mp3'));
      } else {
        _playSystemSound();
      }
      debugPrint('🔊 Test sound played');
    } catch (e) {
      _playSystemSound();
    }
  }

  /// Fallback to system sound
  void _playSystemSound() {
    try {
      SystemSound.play(SystemSoundType.click);
      debugPrint('🔊 System sound played');
    } catch (e) {
      debugPrint('❌ Could not play system sound: $e');
    }
  }

  /// Mute/unmute toggle
  void toggleMute() {
    _isMuted = !_isMuted;
    debugPrint(_isMuted ? '🔇 Sound muted' : '🔊 Sound unmuted');
  }

  /// Mute
  void mute() {
    _isMuted = true;
    debugPrint('🔇 Sound muted');
  }

  /// Unmute
  void unmute() {
    _isMuted = false;
    debugPrint('🔊 Sound unmuted');
  }

  /// Stop playing
  Future<void> stop() async {
    if (!_isInitialized || _audioPlayer == null) return;

    try {
      await _audioPlayer!.stop();
    } catch (e) {
      debugPrint('Error stopping sound: $e');
    }
  }

  /// Dispose
  Future<void> dispose() async {
    if (_audioPlayer != null) {
      await _audioPlayer!.dispose();
      _audioPlayer = null;
    }
    _isInitialized = false;
    debugPrint('🗑️ SoundService disposed');
  }
}
