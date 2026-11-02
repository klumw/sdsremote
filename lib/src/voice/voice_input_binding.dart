import 'package:flutter/foundation.dart';

import 'voice_input_service.dart';

/// Connects one assistant to the shared [VoiceInputService].
///
/// Each of the four AI assistants owns a binding with its own [ownerId]. The
/// assistant's chat window renders the microphone button from it, and the
/// panel calls [detach] when the assistant closes so the microphone starts
/// deactivated the next time the panel is opened.
class VoiceInputBinding {
  const VoiceInputBinding({
    required this.ownerId,
    required this.service,
    required this.onTranscript,
  });

  /// Identifier of the assistant that owns this binding, for example
  /// `control_panel_ai`.
  final String ownerId;

  /// Shared microphone service.
  final VoiceInputService service;

  /// Sends a transcript to the assistant that owns this binding.
  final Future<void> Function(String transcript) onTranscript;

  /// The shared microphone status.
  ValueListenable<VoiceInputStatus> get status => service.status;

  /// Whether this assistant currently owns the microphone session.
  bool get isActive => service.status.value.isActiveFor(ownerId);

  /// Turns the microphone on for this assistant, or off when this assistant
  /// already owns it.
  Future<void> toggle() async {
    if (isActive) {
      await service.stop(ownerId: ownerId);
    } else {
      await service.start(ownerId: ownerId, onTranscript: onTranscript);
    }
  }

  /// Stops the microphone if this assistant still owns it.
  Future<void> detach() => service.stop(ownerId: ownerId);
}
