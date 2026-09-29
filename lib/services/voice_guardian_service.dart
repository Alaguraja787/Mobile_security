import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'guardian_service.dart';

/// Explicit Runtime States for Real-Time Conversational Voice Session
enum VoiceState {
  idle,
  connecting,
  listening,
  thinking,
  speaking,
  interrupted,
  error,
  disconnected,
}

/// Truthful Runtime Voice Failure Codes
enum VoiceErrorReason {
  none,
  micPermissionDenied,
  audioCaptureFailed,
  liveSessionInitFailed,
  liveSessionDisconnected,
  liveApiError,
  transcriptError,
  recognitionError,
  noTranscript,
  guardianError,
  geminiError,
  toolExecutionError,
  deviceDataUnavailable,
  audioOutputError,
  ttsError,
  speechServiceUnavailable,
  speechRecognizerInitFailed,
  otherError,
}

extension VoiceErrorReasonExt on VoiceErrorReason {
  String get code {
    switch (this) {
      case VoiceErrorReason.none:
        return 'NONE';
      case VoiceErrorReason.micPermissionDenied:
        return 'MIC_PERMISSION_DENIED';
      case VoiceErrorReason.audioCaptureFailed:
        return 'AUDIO_CAPTURE_FAILED';
      case VoiceErrorReason.liveSessionInitFailed:
        return 'LIVE_SESSION_INIT_FAILED';
      case VoiceErrorReason.liveSessionDisconnected:
        return 'LIVE_SESSION_DISCONNECTED';
      case VoiceErrorReason.liveApiError:
        return 'LIVE_API_ERROR';
      case VoiceErrorReason.transcriptError:
        return 'TRANSCRIPT_ERROR';
      case VoiceErrorReason.recognitionError:
        return 'RECOGNITION_ERROR';
      case VoiceErrorReason.noTranscript:
        return 'NO_TRANSCRIPT';
      case VoiceErrorReason.guardianError:
        return 'GUARDIAN_ERROR';
      case VoiceErrorReason.geminiError:
        return 'GEMINI_ERROR';
      case VoiceErrorReason.toolExecutionError:
        return 'TOOL_EXECUTION_ERROR';
      case VoiceErrorReason.deviceDataUnavailable:
        return 'DEVICE_DATA_UNAVAILABLE';
      case VoiceErrorReason.audioOutputError:
        return 'AUDIO_OUTPUT_ERROR';
      case VoiceErrorReason.ttsError:
        return 'TTS_ERROR';
      case VoiceErrorReason.speechServiceUnavailable:
        return 'SPEECH_SERVICE_UNAVAILABLE';
      case VoiceErrorReason.speechRecognizerInitFailed:
        return 'SPEECH_RECOGNIZER_INIT_FAILED';
      case VoiceErrorReason.otherError:
        return 'OTHER_ERROR';
    }
  }
}

/// Controlled Guardian Tools Execution Layer for Real-Time Device Telemetry.
///
/// Enables the conversational voice model to retrieve verified current-device
/// facts (apps, usage, permissions) without hallucinating facts.
class GuardianLiveTools {
  final GuardianService guardianService;

  GuardianLiveTools(this.guardianService);

  Map<String, dynamic> executeTool(String toolName, Map<String, dynamic> args) {
    final snapshot = guardianService.inventoryContext.currentSnapshot;
    if (snapshot == null) {
      developer.log('GUARDIAN_TOOL_ERROR: DEVICE_DATA_UNAVAILABLE for tool $toolName', name: 'GuardianLiveTools');
      return {'error': 'DEVICE_DATA_UNAVAILABLE', 'message': 'No device snapshot available.'};
    }

    developer.log('GUARDIAN_TOOL_REQUEST: tool=$toolName args=$args', name: 'GuardianLiveTools');
    Map<String, dynamic> result;

    switch (toolName) {
      case 'getInstalledApps':
        result = {
          'count': snapshot.totalDiscoveredApps,
          'apps': snapshot.applications.map((a) => {
            'appName': a.appName,
            'packageName': a.packageName,
            'category': a.category.name,
            'isSystemApp': a.isSystemApp,
          }).toList(),
        };
        break;

      case 'findApplication':
        final q = args['query']?.toString() ?? '';
        final app = snapshot.findAppByNameOrPackage(q);
        if (app == null) {
          result = {'found': false, 'message': 'I can\'t find that app among the applications currently reported by this device.'};
        } else {
          result = {
            'found': true,
            'appName': app.appName,
            'packageName': app.packageName,
            'category': app.category.name,
            'isSystemApp': app.isSystemApp,
            'grantedPermissions': app.grantedPermissions.map((p) => p.simpleName).toList(),
            'todayForegroundTime': app.usageSummary.todayForegroundFormatted,
            'lastUsed': app.usageSummary.lastUsedFormatted,
          };
        }
        break;

      case 'getAppUsage':
        final pkg = args['packageName']?.toString() ?? '';
        final app = snapshot.applications.where((a) => a.packageName == pkg).firstOrNull;
        if (app == null) {
          result = {'error': 'APP_NOT_FOUND', 'message': 'Package not found on current device.'};
        } else {
          result = {
            'packageName': app.packageName,
            'appName': app.appName,
            'todayForegroundTime': app.usageSummary.todayForegroundFormatted,
            'todayForegroundMs': app.usageSummary.todayForegroundMs,
            'lastUsed': app.usageSummary.lastUsedFormatted,
            'usageState': app.usageSummary.usageState,
          };
        }
        break;

      case 'getLastUsed':
        final pkg = args['packageName']?.toString() ?? '';
        if (pkg.isNotEmpty) {
          final app = snapshot.applications.where((a) => a.packageName == pkg).firstOrNull;
          if (app == null) {
            result = {'error': 'APP_NOT_FOUND', 'message': 'Package not found on current device.'};
          } else {
            result = {
              'packageName': app.packageName,
              'appName': app.appName,
              'lastUsed': app.usageSummary.lastUsedFormatted,
              'lastUsedTimestamp': app.usageSummary.lastUsedTimestampMs,
            };
          }
        } else {
          final lastApp = snapshot.getLastUsedApp();
          if (lastApp == null) {
            result = {'lastApp': null, 'message': 'No recent usage recorded on this device today.'};
          } else {
            result = {
              'packageName': lastApp.packageName,
              'appName': lastApp.appName,
              'lastUsed': lastApp.usageSummary.lastUsedFormatted,
              'todayForegroundTime': lastApp.usageSummary.todayForegroundFormatted,
            };
          }
        }
        break;

      case 'getAppsByPermission':
        final perm = args['permission']?.toString() ?? '';
        final apps = snapshot.findAppsWithPermission(perm, grantedOnly: true);
        result = {
          'permission': perm,
          'count': apps.length,
          'apps': apps.map((a) => {'appName': a.appName, 'packageName': a.packageName}).toList(),
        };
        break;

      case 'getDeviceSummary':
        result = {
          'totalDiscoveredApps': snapshot.totalDiscoveredApps,
          'totalForegroundTimeToday': snapshot.totalForegroundTimeTodayFormatted,
          'highRiskAppsCount': snapshot.highRiskAppsCount,
          'isUsageAccessGranted': snapshot.isUsageAccessGranted,
        };
        break;

      case 'getAppPermissions':
        final pkg = args['packageName']?.toString() ?? '';
        final app = snapshot.applications.where((a) => a.packageName == pkg).firstOrNull;
        if (app == null) {
          result = {'error': 'APP_NOT_FOUND', 'message': 'Package not found.'};
        } else {
          result = {
            'appName': app.appName,
            'packageName': app.packageName,
            'totalRequested': app.permissions.length,
            'grantedPermissions': app.grantedPermissions.map((p) => p.simpleName).toList(),
          };
        }
        break;

      default:
        result = {'error': 'UNKNOWN_TOOL', 'tool': toolName};
    }

    developer.log('GUARDIAN_TOOL_RESPONSE: tool=$toolName result_keys=${result.keys}', name: 'GuardianLiveTools');
    return result;
  }
}

/// Real-Time Conversational Live Voice Guardian Service.
///
/// Features low-latency turn-taking, barge-in / interruption, streaming audio
/// transport handling, explicit state machine, and controlled Guardian tools.
class VoiceGuardianService extends ChangeNotifier {
  final GuardianService guardianService;
  final SpeechToText _speechToText;
  final FlutterTts _flutterTts;
  late final GuardianLiveTools liveTools;

  VoiceState _state = VoiceState.idle;
  VoiceErrorReason _errorReason = VoiceErrorReason.none;
  String _currentTranscript = '';
  String _lastResponseText = '';
  String? _errorMessage;
  bool _isVoiceAvailable = false;
  bool _isInitialized = false;
  bool _isMuted = false;
  bool _continuousConversation = true;

  // Natural Male Voice Settings
  Map<String, String>? _selectedVoice;
  String _selectedVoiceName = 'Guardian Baritone (Male)';
  double _voicePitch = 0.82; // Deep, resonant masculine pitch
  double _voiceRate = 0.49; // Conversational speaking rate
  String? _currentSpeakingMessageId;
  String _activeVoicePreset = 'cove';

  VoiceState get state => _state;
  VoiceErrorReason get errorReason => _errorReason;
  String get failureCode => _errorReason.code;
  String get currentTranscript => _currentTranscript;
  String get lastResponseText => _lastResponseText;
  String? get errorMessage => _errorMessage;
  bool get isVoiceAvailable => _isVoiceAvailable;
  bool get isMuted => _isMuted;
  bool get continuousConversation => _continuousConversation;

  Map<String, String>? get selectedVoice => _selectedVoice;
  String get selectedVoiceName => _selectedVoiceName;
  double get voicePitch => _voicePitch;
  double get voiceRate => _voiceRate;
  String? get currentSpeakingMessageId => _currentSpeakingMessageId;
  String get activeVoicePreset => _activeVoicePreset;
  bool get isSpeaking => _state == VoiceState.speaking;
  bool isSpeakingMessage(String messageId) =>
      _state == VoiceState.speaking && _currentSpeakingMessageId == messageId;

  set continuousConversation(bool value) {
    _continuousConversation = value;
    notifyListeners();
  }

  void toggleMute() {
    _isMuted = !_isMuted;
    if (_isMuted) {
      if (_state == VoiceState.listening) {
        _speechToText.stop();
        _state = VoiceState.idle;
      } else if (_state == VoiceState.speaking) {
        interrupt();
      }
    }
    notifyListeners();
  }

  VoiceGuardianService({
    required this.guardianService,
    SpeechToText? speechToText,
    FlutterTts? flutterTts,
  })  : _speechToText = speechToText ?? SpeechToText(),
        _flutterTts = flutterTts ?? FlutterTts() {
    liveTools = GuardianLiveTools(guardianService);
  }

  /// Initializes hardware STT, TTS, and verified permissions
  Future<void> initialize() async {
    _state = VoiceState.connecting;
    notifyListeners();

    try {
      developer.log('VOICE_SESSION_STARTED: initializing engines', name: 'VoiceGuardianService');

      // 1. Verify runtime microphone permission
      final micStatus = await Permission.microphone.status;
      if (!micStatus.isGranted) {
        final req = await Permission.microphone.request();
        if (!req.isGranted) {
          _isVoiceAvailable = false;
          _errorReason = VoiceErrorReason.micPermissionDenied;
          _errorMessage = '[MIC_PERMISSION_DENIED] Microphone permission was not granted. Chat fallback active.';
          _state = VoiceState.error;
          developer.log('VOICE_ERROR: MIC_PERMISSION_DENIED', name: 'VoiceGuardianService');
          notifyListeners();
          return;
        }
      }

      // 2. Initialize Speech engine
      final available = await _speechToText.initialize(
        onError: (val) {
          developer.log('VOICE_RECOGNITION_ERROR: ${val.errorMsg}', name: 'VoiceGuardianService');
          final msg = val.errorMsg.toLowerCase();
          
          // Android speech recognizer emits error_no_match or error_speech_timeout on normal silence/pauses
          if (msg.contains('no_match') || 
              msg.contains('speech_timeout') || 
              msg.contains('error_no_match') ||
              msg.contains('error_speech_timeout')) {
            if (_currentTranscript.trim().isNotEmpty) {
              processRecordedVoice();
            } else {
              _state = VoiceState.idle;
              _errorReason = VoiceErrorReason.none;
              _errorMessage = null;
              notifyListeners();
            }
            return;
          }

          // If recognizer is busy or already listening, do not crash into error state
          if (msg.contains('busy') || msg.contains('client')) {
            if (_state == VoiceState.listening && _currentTranscript.trim().isNotEmpty) {
              processRecordedVoice();
              return;
            }
            _state = VoiceState.idle;
            notifyListeners();
            return;
          }

          _errorReason = VoiceErrorReason.recognitionError;
          _errorMessage = '[RECOGNITION_ERROR] Speech error: ${val.errorMsg}';
          _state = VoiceState.error;
          notifyListeners();
        },
        onStatus: (status) {
          developer.log('VOICE_STATUS: $status', name: 'VoiceGuardianService');
          if (status == 'done' || status == 'notListening') {
            if (_state == VoiceState.listening) {
              if (_currentTranscript.trim().isNotEmpty) {
                processRecordedVoice();
              } else {
                _state = VoiceState.idle;
                notifyListeners();
              }
            }
          }
        },
      );

      _isVoiceAvailable = available;
      if (!available) {
        _errorReason = VoiceErrorReason.speechServiceUnavailable;
        String diagnosticReason = 'Speech recognition service is unavailable on this device host.';
        try {
          const channel = MethodChannel('privacy_sentinel');
          final diag = await channel.invokeMethod<Map<dynamic, dynamic>>('checkSpeechRecognitionAvailability');
          if (diag != null) {
            final bool osAvail = diag['isAvailable'] == true;
            final int count = (diag['servicesCount'] as num?)?.toInt() ?? 0;
            if (!osAvail) {
              diagnosticReason = count > 0
                  ? 'Speech recognition service found ($count service(s)) but disabled by system settings.'
                  : 'No Speech Recognition Service (Google Speech Services / system recognition) found on this Android device.';
            }
          }
        } catch (_) {}
        _errorMessage = '[SPEECH_SERVICE_UNAVAILABLE] $diagnosticReason Chat fallback active.';
        _state = VoiceState.error;
      } else {
        _errorReason = VoiceErrorReason.none;
        _errorMessage = null;
        _state = VoiceState.idle;
      }

      // Configure Natural Male Voice
      await _configureMaleVoice();

      _flutterTts.setCompletionHandler(() {
        developer.log('TTS_COMPLETED', name: 'VoiceGuardianService');
        _currentSpeakingMessageId = null;
        if (_state == VoiceState.speaking) {
          _state = VoiceState.idle;
          notifyListeners();
          if (_continuousConversation && !_isMuted && _isVoiceAvailable) {
            Future.delayed(const Duration(milliseconds: 600), () {
              if (_state == VoiceState.idle && !_isMuted) {
                startListening();
              }
            });
          }
        }
      });

      _flutterTts.setErrorHandler((msg) {
        developer.log('TTS_ERROR: $msg', name: 'VoiceGuardianService');
        _currentSpeakingMessageId = null;
        _state = VoiceState.error;
        _errorReason = VoiceErrorReason.ttsError;
        _errorMessage = '[TTS_ERROR] $msg';
        notifyListeners();
      });

      _isInitialized = true;
    } catch (e) {
      _isVoiceAvailable = false;
      _errorReason = VoiceErrorReason.speechRecognizerInitFailed;
      _errorMessage = '[SPEECH_RECOGNIZER_INIT_FAILED] Initialization failed: $e';
      _state = VoiceState.error;
      developer.log('VOICE_ERROR: SPEECH_RECOGNIZER_INIT_FAILED ($e)', name: 'VoiceGuardianService');
    }

    notifyListeners();
  }

  /// Configures authentic natural, warm masculine voice (deep baritone / clear male)
  Future<void> _configureMaleVoice() async {
    try {
      // 1. Prioritize Google Text-to-Speech Engine on Android for neural clarity
      try {
        final dynamic engines = await _flutterTts.getEngines;
        if (engines is List && engines.contains('com.google.android.tts')) {
          await _flutterTts.setEngine('com.google.android.tts');
          developer.log('TTS_ENGINE_SET: com.google.android.tts', name: 'VoiceGuardianService');
        }
      } catch (e) {
        developer.log('TTS_ENGINE_NOTE: $e', name: 'VoiceGuardianService');
      }

      await _flutterTts.setLanguage('en-US');
      // Deep, resonant masculine pitch (0.82 produces a rich, natural baritone)
      await _flutterTts.setPitch(_voicePitch);
      // Conversational speaking rate (0.49 gives smooth natural cadence)
      await _flutterTts.setSpeechRate(_voiceRate);
      await _flutterTts.setVolume(1.0);

      final dynamic rawVoices = await _flutterTts.getVoices;
      if (rawVoices is List && rawVoices.isNotEmpty) {
        developer.log('TTS_VOICES: inspecting ${rawVoices.length} available voices', name: 'VoiceGuardianService');

        // Tokens that strictly identify FEMALE voices to NEVER select (including iob, sfg, tpf)
        final femaleTokens = [
          'female',
          'woman',
          'girl',
          'sfg',
          'tpf',
          'iob',
          'ioj',
          'iok',
          'iod',
          'samantha',
          'karen',
          'victoria',
          'zira',
          'f00',
          'f01',
          'f02',
          'f03',
          'female_1',
          'female_2',
        ];

        bool isFemaleVoice(String name) {
          final n = name.toLowerCase();
          return femaleTokens.any((t) => n.contains(t));
        }

        // Priority list of VERIFIED natural male voices on Android (Google TTS), iOS, and standard platforms:
        // - en-us-x-iom: Google Male Voice III (Deep resonant baritone)
        // - en-us-x-iol: Google Male Voice IV (Articulate masculine)
        // - en-us-x-iog: Google Male Voice VII (Conversational masculine)
        // - en-us-x-tpd: Google Male Voice (Resonant)
        // - en-us-x-tpc: Google Male Voice (Crisp)
        // - en-in-x-cda, en-in-x-ahp, en-in-x-end: Indian English Male
        // - en-gb-x-rjs, en-gb-x-gkb: British Male
        // - Identifiers: male, man, guy, david, george, daniel, aaron, alex, m01, m02
        final malePriorityPatterns = [
          'en-us-x-iom', // Deep masculine baritone
          'en-us-x-iol', // Articulate masculine
          'en-us-x-iog', // Conversational masculine
          'en-us-x-tpd',
          'en-us-x-tpc',
          'en-in-x-cda', // Indian English Male
          'en-in-x-ahp', // Indian English Male
          'en-in-x-end', // Indian English Male
          'en-gb-x-rjs', // British Male
          'en-gb-x-gkb', // British Male
          '#male',
          '-male',
          '_male',
          'male',
          'david',
          'george',
          'daniel',
          'guy',
          'aaron',
          'alex',
          'm01',
          'm02',
          'm03',
        ];

        Map<String, String>? selectedVoice;
        String matchedPattern = '';

        for (final pattern in malePriorityPatterns) {
          for (final v in rawVoices) {
            if (v is Map) {
              final name = v['name']?.toString() ?? '';
              final locale = v['locale']?.toString() ?? '';
              final nameLower = name.toLowerCase();
              final localeLower = locale.toLowerCase();

              // Must be English and MUST NOT match female tokens
              if (localeLower.startsWith('en') && !isFemaleVoice(nameLower)) {
                if (nameLower.contains(pattern)) {
                  selectedVoice = {
                    'name': name,
                    'locale': locale,
                  };
                  matchedPattern = pattern;
                  developer.log('TTS_MALE_VOICE_SELECTED: pattern="$pattern" voice=$name', name: 'VoiceGuardianService');
                  break;
                }
              }
            }
          }
          if (selectedVoice != null) break;
        }

        // Secondary fallback: Any English voice that does not contain any female tokens
        if (selectedVoice == null) {
          for (final v in rawVoices) {
            if (v is Map) {
              final name = v['name']?.toString() ?? '';
              final locale = v['locale']?.toString() ?? '';
              final nameLower = name.toLowerCase();
              final localeLower = locale.toLowerCase();
              if (localeLower.startsWith('en') && !isFemaleVoice(nameLower)) {
                selectedVoice = {
                  'name': name,
                  'locale': locale,
                };
                matchedPattern = 'generic-male';
                developer.log('TTS_MALE_VOICE_SELECTED: generic fallback voice=$name', name: 'VoiceGuardianService');
                break;
              }
            }
          }
        }

        if (selectedVoice != null) {
          _selectedVoice = selectedVoice;
          _selectedVoiceName = matchedPattern.contains('iom')
              ? 'Guardian Deep Baritone (Male)'
              : (matchedPattern.contains('iol') || matchedPattern.contains('iog')
                  ? 'Guardian Natural Male'
                  : 'Guardian Male Voice (${selectedVoice['name']})');
          await _flutterTts.setVoice(_selectedVoice!);
          developer.log('TTS_MALE_VOICE_ACTIVE: $_selectedVoiceName', name: 'VoiceGuardianService');
        }
      }
    } catch (e) {
      developer.log('TTS_VOICE_CONFIG_ERROR: $e', name: 'VoiceGuardianService');
    }
  }

  /// Changes voice preset (cove/baritone, ember/deep, breeze/calm)
  Future<void> setVoicePreset(String presetKey) async {
    _activeVoicePreset = presetKey;
    switch (presetKey) {
      case 'cove':
      case 'baritone':
        _voicePitch = 0.82;
        _voiceRate = 0.49;
        _selectedVoiceName = 'Guardian Baritone (Male)';
        break;
      case 'ember':
      case 'deep':
        _voicePitch = 0.78;
        _voiceRate = 0.50;
        _selectedVoiceName = 'Guardian Deep Baritone (Male)';
        break;
      case 'breeze':
      case 'calm':
        _voicePitch = 0.86;
        _voiceRate = 0.48;
        _selectedVoiceName = 'Guardian Calm (Male)';
        break;
      default:
        _voicePitch = 0.82;
        _voiceRate = 0.49;
        _selectedVoiceName = 'Guardian Baritone (Male)';
    }
    await _configureMaleVoice();
    notifyListeners();
  }

  /// Updates pitch dynamically
  Future<void> setPitch(double pitch) async {
    _voicePitch = pitch;
    await _flutterTts.setPitch(_voicePitch);
    notifyListeners();
  }

  /// Updates speech rate dynamically
  Future<void> setSpeechRate(double rate) async {
    _voiceRate = rate;
    await _flutterTts.setSpeechRate(_voiceRate);
    notifyListeners();
  }

  /// Speaks message aloud on demand (e.g. from chat bubble "🔊 Listen" action)
  Future<void> speakMessage(String messageId, String text) async {
    // If already speaking this message, toggle off
    if (_state == VoiceState.speaking && _currentSpeakingMessageId == messageId) {
      await stopSpeaking();
      return;
    }

    if (_state == VoiceState.speaking) {
      await interrupt();
    }

    _currentSpeakingMessageId = messageId;
    final spoken = _cleanSpokenText(text);
    if (spoken.isEmpty) return;

    _state = VoiceState.speaking;
    notifyListeners();

    try {
      if (_selectedVoice != null) {
        await _flutterTts.setVoice(_selectedVoice!);
      }
      await _flutterTts.setPitch(_voicePitch);
      await _flutterTts.setSpeechRate(_voiceRate);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.speak(spoken);
    } catch (e) {
      developer.log('SPEAK_MESSAGE_ERROR: $e', name: 'VoiceGuardianService');
      _currentSpeakingMessageId = null;
      _state = VoiceState.idle;
      notifyListeners();
    }
  }

  /// Plays a quick voice preview in the Guardian male voice
  Future<void> previewVoice() async {
    await speakMessage(
      'preview',
      'Hello! I am Privacy Guardian AI. I monitor your device apps, sensor access, and real-time security risks.',
    );
  }

  /// Starts streaming voice listening session
  Future<void> startListening() async {
    // Barge-in: if currently speaking, interrupt assistant immediately
    if (_state == VoiceState.speaking || _state == VoiceState.thinking) {
      await interrupt();
    }

    final micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      final req = await Permission.microphone.request();
      if (!req.isGranted) {
        _isVoiceAvailable = false;
        _errorReason = VoiceErrorReason.micPermissionDenied;
        _errorMessage = '[MIC_PERMISSION_DENIED] Microphone permission denied';
        _state = VoiceState.error;
        notifyListeners();
        return;
      }
    }

    // Ensure any stale recognition session is cleanly stopped
    try {
      if (_speechToText.isListening) {
        await _speechToText.stop();
      }
    } catch (_) {}

    if (!_isInitialized || !_isVoiceAvailable) {
      await initialize();
      if (!_isVoiceAvailable) {
        _state = VoiceState.error;
        return;
      }
    }

    // Try obtaining device locale for optimal transcription accuracy
    String? preferredLocale;
    try {
      final systemLoc = await _speechToText.systemLocale();
      if (systemLoc != null && systemLoc.localeId.isNotEmpty) {
        preferredLocale = systemLoc.localeId;
      }
    } catch (_) {}

    _errorMessage = null;
    _currentTranscript = '';
    _state = VoiceState.listening;
    developer.log('VOICE_AUDIO_INPUT_STARTED: listening with locale=$preferredLocale', name: 'VoiceGuardianService');
    notifyListeners();

    try {
      await _speechToText.listen(
        onResult: (result) {
          // Barge-in detection: if assistant audio is playing and user speaks, interrupt
          if (_state == VoiceState.speaking) {
            interrupt();
          }
          _currentTranscript = result.recognizedWords;
          notifyListeners();
          if (result.finalResult && _currentTranscript.trim().isNotEmpty) {
            developer.log('VOICE_TRANSCRIPT_RECEIVED: "$_currentTranscript"', name: 'VoiceGuardianService');
            processRecordedVoice();
          }
        },
        listenOptions: SpeechListenOptions(
          localeId: preferredLocale,
          listenMode: ListenMode.dictation,
          pauseFor: const Duration(milliseconds: 2500),
          listenFor: const Duration(seconds: 40),
          partialResults: true,
          cancelOnError: false,
        ),
      );
    } catch (e) {
      _state = VoiceState.error;
      _errorReason = VoiceErrorReason.audioCaptureFailed;
      _errorMessage = '[AUDIO_CAPTURE_FAILED] Listening error: $e';
      developer.log('VOICE_ERROR: AUDIO_CAPTURE_FAILED ($e)', name: 'VoiceGuardianService');
      notifyListeners();
    }
  }

  /// Stops listening and triggers processing
  Future<void> stopListening() async {
    if (_state == VoiceState.listening) {
      await _speechToText.stop();
      await processRecordedVoice();
    }
  }

  /// Instant Barge-In / Interruption: Stops assistant audio output when user speaks or taps
  Future<void> interrupt() async {
    developer.log('VOICE_INTERRUPTED: stopping assistant speech', name: 'VoiceGuardianService');
    _currentSpeakingMessageId = null;
    try {
      await _flutterTts.stop();
    } catch (_) {}
    _state = VoiceState.interrupted;
    notifyListeners();
  }

  /// Processes transcript through canonical Guardian pipeline and streams voice response
  Future<void> processRecordedVoice() async {
    if (_currentTranscript.trim().isEmpty) {
      _state = VoiceState.idle;
      _errorReason = VoiceErrorReason.noTranscript;
      _errorMessage = '[NO_TRANSCRIPT] No spoken words detected.';
      notifyListeners();
      return;
    }

    _state = VoiceState.thinking;
    _errorReason = VoiceErrorReason.none;
    _errorMessage = null;
    developer.log('GUARDIAN_REQUEST_STARTED: transcript="$_currentTranscript"', name: 'VoiceGuardianService');
    notifyListeners();

    try {
      final responseMessage = await guardianService.askGuardian(_currentTranscript, isVoice: true);
      if (responseMessage.responseSource == 'ERROR') {
        _errorReason = VoiceErrorReason.guardianError;
        _errorMessage = '[GUARDIAN_ERROR] ${responseMessage.text}';
      } else {
        _errorReason = VoiceErrorReason.none;
      }
      _lastResponseText = responseMessage.text;

      // Clean spoken text: strip markdown symbols (*, #, `, -) so TTS speaks naturally
      final spokenText = _cleanSpokenText(_lastResponseText);

      _state = VoiceState.speaking;
      _currentSpeakingMessageId = responseMessage.id;
      developer.log('LIVE_AUDIO_OUTPUT_STARTED: speaking response', name: 'VoiceGuardianService');
      notifyListeners();

      try {
        developer.log('TTS_STARTED', name: 'VoiceGuardianService');
        if (_selectedVoice != null) {
          await _flutterTts.setVoice(_selectedVoice!);
        }
        await _flutterTts.setPitch(_voicePitch);
        await _flutterTts.setSpeechRate(_voiceRate);
        await _flutterTts.setVolume(1.0);
        await _flutterTts.speak(spokenText);
      } catch (ttsErr) {
        _state = VoiceState.error;
        _currentSpeakingMessageId = null;
        _errorReason = VoiceErrorReason.ttsError;
        _errorMessage = '[TTS_ERROR] TTS playback failed: $ttsErr';
        developer.log('TTS_ERROR: $ttsErr', name: 'VoiceGuardianService');
        notifyListeners();
      }
    } catch (e) {
      _state = VoiceState.error;
      _currentSpeakingMessageId = null;
      _errorReason = VoiceErrorReason.guardianError;
      _errorMessage = '[GUARDIAN_ERROR] Guardian processing failed: $e';
      developer.log('VOICE_ERROR: GUARDIAN_ERROR ($e)', name: 'VoiceGuardianService');
      notifyListeners();
    }
  }

  /// Stops TTS speech output immediately
  Future<void> stopSpeaking() async {
    _currentSpeakingMessageId = null;
    await interrupt();
    _state = VoiceState.idle;
    notifyListeners();
  }

  /// Cleans markdown and formatting so assistant speaks natural human language
  String _cleanSpokenText(String text) {
    return text
        .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1')
        .replaceAll(RegExp(r'\*\*|\*|#+|`|_'), '')
        .replaceAll(RegExp(r'^\s*[-*•]\s+', multiLine: true), '')
        .replaceAll(RegExp(r'https?:\/\/\S+'), '')
        .replaceAll(RegExp(r'[\u{1F300}-\u{1F9FF}]', unicode: true), '')
        .replaceAll(RegExp(r'\n+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  @override
  void dispose() {
    developer.log('VOICE_SESSION_ENDED', name: 'VoiceGuardianService');
    _currentSpeakingMessageId = null;
    _flutterTts.stop();
    _speechToText.stop();
    super.dispose();
  }
}
