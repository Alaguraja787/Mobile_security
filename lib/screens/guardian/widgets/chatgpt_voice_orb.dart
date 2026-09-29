import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../services/voice_guardian_service.dart';

/// ChatGPT-style luminous pulsating fluid voice orb with reactive state visuals.
class GuardianVoiceOrb extends StatefulWidget {
  final VoiceState state;
  final bool isVoiceAvailable;
  final VoidCallback? onTap;
  final double size;

  const GuardianVoiceOrb({
    super.key,
    required this.state,
    this.isVoiceAvailable = true,
    this.onTap,
    this.size = 200.0,
  });

  @override
  State<GuardianVoiceOrb> createState() => _GuardianVoiceOrbState();
}

class _GuardianVoiceOrbState extends State<GuardianVoiceOrb>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _rotationController;
  late final AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _updateAnimationSpeeds();
  }

  @override
  void didUpdateWidget(covariant GuardianVoiceOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _updateAnimationSpeeds();
    }
  }

  void _updateAnimationSpeeds() {
    switch (widget.state) {
      case VoiceState.speaking:
        _pulseController.duration = const Duration(milliseconds: 800);
        _rotationController.duration = const Duration(seconds: 4);
        _waveController.duration = const Duration(milliseconds: 600);
        break;
      case VoiceState.listening:
        _pulseController.duration = const Duration(milliseconds: 1200);
        _rotationController.duration = const Duration(seconds: 6);
        _waveController.duration = const Duration(milliseconds: 900);
        break;
      case VoiceState.thinking:
        _pulseController.duration = const Duration(milliseconds: 1000);
        _rotationController.duration = const Duration(seconds: 3);
        _waveController.duration = const Duration(milliseconds: 800);
        break;
      case VoiceState.connecting:
        _pulseController.duration = const Duration(milliseconds: 1500);
        _rotationController.duration = const Duration(seconds: 5);
        _waveController.duration = const Duration(milliseconds: 1100);
        break;
      case VoiceState.idle:
      default:
        _pulseController.duration = const Duration(milliseconds: 2200);
        _rotationController.duration = const Duration(seconds: 14);
        _waveController.duration = const Duration(milliseconds: 1600);
        break;
    }
    if (_pulseController.isAnimating) _pulseController.repeat(reverse: true);
    if (_rotationController.isAnimating) _rotationController.repeat();
    if (_waveController.isAnimating) _waveController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotationController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  List<Color> _getGradientColors() {
    switch (widget.state) {
      case VoiceState.speaking:
        return const [
          Color(0xFF00F2FE),
          Color(0xFF4FACFE),
          Color(0xFF6366F1),
          Color(0xFF10B981),
        ];
      case VoiceState.listening:
        return const [
          Color(0xFF10B981),
          Color(0xFF06B6D4),
          Color(0xFF3B82F6),
          Color(0xFF10B981),
        ];
      case VoiceState.thinking:
        return const [
          Color(0xFF8B5CF6),
          Color(0xFF6366F1),
          Color(0xFFEC4899),
          Color(0xFF3B82F6),
        ];
      case VoiceState.error:
        return const [
          Color(0xFF6366F1),
          Color(0xFFF59E0B),
          Color(0xFF8B5CF6),
        ];
      case VoiceState.connecting:
        return const [
          Color(0xFF06B6D4),
          Color(0xFF6366F1),
          Color(0xFF8B5CF6),
        ];
      case VoiceState.idle:
      default:
        return const [
          Color(0xFF6366F1),
          Color(0xFF8B5CF6),
          Color(0xFF06B6D4),
          Color(0xFF3B82F6),
        ];
    }
  }

  IconData _getStateIcon() {
    switch (widget.state) {
      case VoiceState.speaking:
        return Icons.graphic_eq_rounded;
      case VoiceState.listening:
        return Icons.mic_rounded;
      case VoiceState.thinking:
        return Icons.auto_awesome_rounded;
      case VoiceState.connecting:
        return Icons.sync_rounded;
      case VoiceState.error:
        return Icons.mic_none_rounded;
      case VoiceState.idle:
      default:
        return Icons.mic_none_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _getGradientColors();

    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: Listenable.merge([_pulseController, _rotationController, _waveController]),
          builder: (context, child) {
            final pulse = _pulseController.value;
            final rotation = _rotationController.value * 2 * math.pi;
            final wave = _waveController.value;

            final scale = 0.92 + (pulse * 0.12);
            final outerGlowOpacity = (0.2 + (pulse * 0.25)).clamp(0.0, 1.0);

            return Transform.scale(
              scale: scale,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer Glow aura
                  Container(
                    width: widget.size * 0.95,
                    height: widget.size * 0.95,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: colors.first.withValues(alpha: outerGlowOpacity * 0.5),
                          blurRadius: 40 + (pulse * 20),
                          spreadRadius: 8 + (wave * 12),
                        ),
                        BoxShadow(
                          color: colors.length > 1
                              ? colors[1].withValues(alpha: outerGlowOpacity * 0.4)
                              : colors.first.withValues(alpha: outerGlowOpacity * 0.4),
                          blurRadius: 55,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                  ),

                  // Rotating Gradient Ring
                  Transform.rotate(
                    angle: rotation,
                    child: Container(
                      width: widget.size * 0.82,
                      height: widget.size * 0.82,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: SweepGradient(
                          colors: [
                            ...colors,
                            colors.first,
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Middle blur frosted sphere
                  Transform.rotate(
                    angle: -rotation * 0.6,
                    child: Container(
                      width: widget.size * 0.76,
                      height: widget.size * 0.76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          center: Alignment(
                            math.sin(rotation) * 0.35,
                            math.cos(rotation) * 0.35,
                          ),
                          radius: 0.85,
                          colors: [
                            Colors.white.withValues(alpha: 0.9),
                            colors.first.withValues(alpha: 0.7),
                            colors.last.withValues(alpha: 0.4),
                            const Color(0xFF0B0F19).withValues(alpha: 0.2),
                          ],
                          stops: const [0.0, 0.35, 0.7, 1.0],
                        ),
                      ),
                    ),
                  ),

                  // Core Luminous Nucleus
                  Container(
                    width: widget.size * 0.45,
                    height: widget.size * 0.45,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF0F172A).withValues(alpha: 0.85),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3 + (wave * 0.2)),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.3),
                          blurRadius: 15,
                          spreadRadius: -2,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        _getStateIcon(),
                        size: 32,
                        color: Colors.white.withValues(alpha: 0.95),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
