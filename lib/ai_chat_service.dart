import 'dart:convert';
import 'dart:io';
import 'dart:async';

class AiChatService {
  Process? _dockerProcess;
  StreamSubscription<String>? _stdoutSub;
  StreamController<String>? _currentResponseController;

  bool _isDisposed = false;

  Future<void> _initProcess() async {
    if (_dockerProcess != null || _isDisposed) return;

    _stdoutSub?.cancel();

    // Use 'docker exec -i' to start a new process in the container.
    // This ensures that when the process finishes its response, we get a real EOF.
    // We use the entrypoint command found via inspect.
    _dockerProcess = await Process.start('docker', [
      'exec',
      '-i',
      'sds-ai-server',
      '/bin/bash',
      '-c',
      'exec \${APP_SOURCE}/neuro_san/deploy/start_services.sh'
    ]);

    // Drain stderr but don't do anything with it to prevent the process from hanging
    // if the buffer fills up, while ensuring we only "read" (process) data from stdout.
    _dockerProcess!.stderr.listen((_) {});

    _stdoutSub = _dockerProcess!.stdout.transform(utf8.decoder).listen(
      (data) {
        if (_currentResponseController != null &&
            !_currentResponseController!.isClosed) {
          _currentResponseController!.add(data);
        }
      },
      onDone: () {
        if (_currentResponseController != null &&
            !_currentResponseController!.isClosed) {
          _currentResponseController!.close();
          _currentResponseController = null;
        }
      },
      onError: (e) {
        if (_currentResponseController != null &&
            !_currentResponseController!.isClosed) {
          _currentResponseController!.add("\nStream Error: $e\n");
          _currentResponseController!.close();
          _currentResponseController = null;
        }
      },
    );
  }

  /// Sends a message to the AI server over stdio and returns a stream of response chunks.
  Stream<String> sendMessageStream({
    required String text,
    String agentName = 'sds',
  }) async* {
    if (_isDisposed) throw Exception("Service is disposed");

    _currentResponseController = StreamController<String>();

    try {
      await _initProcess();
    } catch (e) {
      yield "Error: Failed to start AI process ($e)";
      return;
    }

    if (_dockerProcess == null) {
      yield "Error: Not connected to docker container.";
      return;
    }

    // 1. Send the request text followed by an empty line to signal completion
    _dockerProcess!.stdin.write('$text\n\n');
    await _dockerProcess!.stdin.flush();
    
    // 2. Close stdin to signal EOF to the server for the request
    await _dockerProcess!.stdin.close();

    // 3. Wait for the response until EOF (onDone of the stdout stream)
    await for (final chunk in _currentResponseController!.stream) {
      yield chunk;
    }

    // Cleanup for next message
    _dockerProcess = null;
  }

  void dispose() {
    _isDisposed = true;
    _currentResponseController?.close();
    _stdoutSub?.cancel();
    _dockerProcess?.stdin.close(); // Detach from the container without killing it
    _dockerProcess = null;
  }
}

