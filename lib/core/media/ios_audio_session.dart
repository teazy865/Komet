import 'dart:io';

import 'package:flutter/services.dart';

/// Forces iOS AVAudioSession category to playback so voice messages
/// are audible even when the hardware mute switch is on.
class IosAudioSession {
  static const _channel = MethodChannel('komet/audio_session');

  static Future<void> ensurePlayback() async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod('setPlayback');
    } catch (_) {
      // Native side may not be implemented yet; ignore.
    }
  }
}
