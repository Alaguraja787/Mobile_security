import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../services/guardian_service.dart';
import '../../services/voice_guardian_service.dart';
import '../../services/llm/llm_config.dart';
import 'widgets/chatgpt_voice_orb.dart';
import 'widgets/voice_settings_sheet.dart';

class GuardianAssistantScreen extends StatefulWidget {
  const GuardianAssistantScreen({super.key});

  @override
  State<GuardianAssistantScreen> createState() => _GuardianAssistantScreenState();
}

class _GuardianAssistantScreenState extends State<GuardianAssistantScreen> with SingleTickerProviderStateMixin {
  bool _isVoiceMode = false;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isThinking = false;
  bool _showSuggestions = false;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _messages.add(ChatMessage(
      id: 'welcome',
      text: 'Hello! I am Privacy Guardian AI. Ask me anything about your connected device apps, active permissions, background access, or privacy risks.',
      isUser: false,
      timestamp: DateTime.now(),
    ));
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage(GuardianService guardian, String text) async {
    if (text.trim().isEmpty) return;

    final userMsg = ChatMessage(
      id: 'usr_${DateTime.now().millisecondsSinceEpoch}',
      text: text.trim(),
      isUser: true,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(userMsg);
      _isThinking = true;
      _showSuggestions = false;
    });

    _textController.clear();
    _scrollToBottom();

    final responseMsg = await guardian.askGuardian(text.trim());

    if (!mounted) return;
    setState(() {
      _messages.add(responseMsg);
      _isThinking = false;
    });

    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearChat() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131A2B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0x336366F1))),
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: AppColors.statusAttention, size: 22),
            SizedBox(width: 8),
            Text('Reset Conversation?', style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
          ],
        ),
        content: const Text(
          'This will clear the current chat history. Real-time telemetry monitoring remains active.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.statusAttention,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _messages.clear();
                _messages.add(ChatMessage(
                  id: 'welcome',
                  text: 'Hello! I am Privacy Guardian AI. Ask me anything about your connected device apps, active permissions, background access, or privacy risks.',
                  isUser: false,
                  timestamp: DateTime.now(),
                ));
              });
            },
            child: const Text('Reset', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final guardianService = Provider.of<GuardianService>(context);
    final voiceService = Provider.of<VoiceGuardianService>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF090B10),
      appBar: _buildCustomAppBar(context, voiceService),
      body: _isVoiceMode
          ? _buildVoiceGuardianUI(voiceService)
          : _buildChatGuardianUI(guardianService, voiceService),
    );
  }

  // ---------------------------------------------------------------------------
  // 🌟 ULTRA-MODERN APP BAR
  // ---------------------------------------------------------------------------
  PreferredSizeWidget _buildCustomAppBar(BuildContext context, VoiceGuardianService voice) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(68),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xEE0B0F19),
          border: Border(bottom: BorderSide(color: Color(0x226366F1), width: 1)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                // Glowing Shield Icon
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF6366F1), Color(0xFF06B6D4)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x336366F1),
                        blurRadius: 10,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(Icons.shield_rounded, color: Colors.white, size: 20),
                  ),
                ),
                const SizedBox(width: 10),

                // Title & Live Status
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Row(
                        children: [
                          Text(
                            'Guardian AI',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: LlmConfig.hasApiKey ? AppColors.statusNormal : AppColors.statusReview,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: (LlmConfig.hasApiKey ? AppColors.statusNormal : AppColors.statusReview).withValues(alpha: 0.6),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              LlmConfig.hasApiKey ? '${LlmConfig.model} • Online' : 'Rule-Based Engine',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                color: LlmConfig.hasApiKey ? AppColors.statusNormal : AppColors.statusReview,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Voice Settings Action (Guardian Male Voice)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => VoiceSettingsSheet.show(context),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0x336366F1)),
                    ),
                    child: const Icon(Icons.tune_rounded, color: AppColors.primary, size: 16),
                  ),
                ),

                // Clear Chat History Action
                if (!_isVoiceMode && _messages.length > 1) ...[
                  const SizedBox(width: 4),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _clearChat,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: const Icon(Icons.refresh_rounded, color: AppColors.textMuted, size: 16),
                    ),
                  ),
                ],
                const SizedBox(width: 8),

                // Custom Sliding Mode Switcher Pill [Chat | Voice]
                _buildModeSwitcher(voice),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeSwitcher(VoiceGuardianService voice) {
    return Container(
      width: 126,
      height: 34,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x336366F1)),
      ),
      child: Stack(
        children: [
          // Animated Sliding Pill
          AnimatedAlign(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOutCubic,
            alignment: _isVoiceMode ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 58,
              height: 28,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x446366F1),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
          // Clickable Tabs
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (_isVoiceMode) {
                      setState(() => _isVoiceMode = false);
                      if (voice.state == VoiceState.listening) {
                        voice.stopListening();
                      }
                    }
                  },
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 13,
                          color: !_isVoiceMode ? Colors.white : Colors.white60,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          'Chat',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: !_isVoiceMode ? FontWeight.bold : FontWeight.w500,
                            color: !_isVoiceMode ? Colors.white : Colors.white60,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (!_isVoiceMode) {
                      setState(() => _isVoiceMode = true);
                      voice.startListening();
                    }
                  },
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.mic_none_rounded,
                          size: 14,
                          color: _isVoiceMode ? Colors.white : Colors.white60,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          'Voice',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: _isVoiceMode ? FontWeight.bold : FontWeight.w500,
                            color: _isVoiceMode ? Colors.white : Colors.white60,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 💬 CHAT GUARDIAN UI
  // ---------------------------------------------------------------------------
  Widget _buildChatGuardianUI(GuardianService guardian, VoiceGuardianService voice) {
    final bool showHero = _messages.length <= 1;

    return Column(
      children: [
        // Main conversation view
        Expanded(
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // Hero Welcome section if conversation is just starting
              if (showHero) _buildHeroWelcomeSection(guardian),

              // Conversation message stream
              ..._messages.map((msg) => _buildModernChatBubble(msg, voice)),

              // Thinking Reasoning Card
              if (_isThinking) _buildThinkingIndicator(),
            ],
          ),
        ),

        // Quick Suggestion Chips (Toggled or Contextual)
        if (_showSuggestions) _buildSuggestionsRow(guardian),

        // Floating Glass Input Bar
        _buildModernInputBar(guardian, voice),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 🛡️ HERO WELCOME INTELLIGENCE HUB
  // ---------------------------------------------------------------------------
  Widget _buildHeroWelcomeSection(GuardianService guardian) {
    final snapshot = guardian.inventoryContext.currentSnapshot;
    final totalApps = snapshot?.totalDiscoveredApps ?? 0;
    final highRiskCount = snapshot?.highRiskAppsCount ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: Column(
        children: [
          const SizedBox(height: 12),
          // Pulsing AI Hologram Orb
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [
                    Color(0xFF6366F1),
                    Color(0xFF06B6D4),
                    Colors.transparent,
                  ],
                  stops: [0.1, 0.65, 1.0],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                    blurRadius: 30,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF0B0F19),
                  ),
                  child: const Icon(
                    Icons.security_rounded,
                    color: AppColors.primary,
                    size: 28,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Hero Typography
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xFFF9FAFB), Color(0xFF818CF8), Color(0xFF06B6D4)],
            ).createShader(bounds),
            child: const Text(
              'Guardian Intelligence',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Real-time AI privacy sentinel analyzing on-device permissions, active sensor access, background telemetry & threat risks.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Live Device Status Glass Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF131A2B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x336366F1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildLiveTelemetryPill(
                  icon: Icons.phone_android,
                  label: 'Pixel 6',
                  sublabel: 'Connected',
                  color: AppColors.statusNormal,
                ),
                Container(width: 1, height: 26, color: Colors.white12),
                _buildLiveTelemetryPill(
                  icon: Icons.apps,
                  label: '$totalApps Apps',
                  sublabel: 'Monitored',
                  color: AppColors.primary,
                ),
                Container(width: 1, height: 26, color: Colors.white12),
                _buildLiveTelemetryPill(
                  icon: Icons.warning_amber_rounded,
                  label: '$highRiskCount High Risk',
                  sublabel: highRiskCount > 0 ? 'Needs Review' : 'Clean',
                  color: highRiskCount > 0 ? AppColors.statusReview : AppColors.statusNormal,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Recommended Prompts Title
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, size: 14, color: AppColors.primary),
                SizedBox(width: 6),
                Text(
                  'QUICK SECURITY AUDIT ACTIONS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 2x2 Interactive Quick Prompt Cards Grid
          _buildQuickActionCard(
            guardian: guardian,
            icon: Icons.mic_external_on,
            iconColor: const Color(0xFF06B6D4),
            title: 'Camera & Mic Access',
            subtitle: 'Which apps have accessed camera or mic today?',
            prompt: 'Which apps have accessed my camera or microphone today?',
          ),
          const SizedBox(height: 8),
          _buildQuickActionCard(
            guardian: guardian,
            icon: Icons.security_outlined,
            iconColor: const Color(0xFFEF4444),
            title: 'High-Risk Permission Audit',
            subtitle: 'Scan for apps with suspicious or dangerous access',
            prompt: 'Identify any high-risk apps with dangerous permissions on this device.',
          ),
          const SizedBox(height: 8),
          _buildQuickActionCard(
            guardian: guardian,
            icon: Icons.history,
            iconColor: const Color(0xFF8B5CF6),
            title: 'Recent App Activity',
            subtitle: 'Review foreground time and last active applications',
            prompt: 'Which applications were active today and for how long?',
          ),
          const SizedBox(height: 8),
          _buildQuickActionCard(
            guardian: guardian,
            icon: Icons.verified_user_rounded,
            iconColor: const Color(0xFF10B981),
            title: 'Device Privacy Score',
            subtitle: 'Generate full privacy & diagnostic safety assessment',
            prompt: 'Provide a complete security and privacy diagnostic score for this device.',
          ),
        ],
      ),
    );
  }

  Widget _buildLiveTelemetryPill({
    required IconData icon,
    required String label,
    required String sublabel,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              sublabel,
              style: TextStyle(
                fontSize: 9,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickActionCard({
    required GuardianService guardian,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String prompt,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _sendMessage(guardian, prompt),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x2A6366F1)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x11000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: iconColor.withValues(alpha: 0.25)),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 14),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 💬 MODERN CHAT BUBBLE
  // ---------------------------------------------------------------------------
  Widget _buildModernChatBubble(ChatMessage msg, VoiceGuardianService voice) {
    final bool isUser = msg.isUser;
    final bool isSpeaking = voice.isSpeakingMessage(msg.id);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.86),
        decoration: BoxDecoration(
          gradient: isUser
              ? const LinearGradient(
                  colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isUser ? null : const Color(0xFF131A2B),
          borderRadius: BorderRadius.circular(20).copyWith(
            bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(20),
            bottomLeft: isUser ? const Radius.circular(20) : const Radius.circular(4),
          ),
          border: isUser ? null : Border.all(color: const Color(0x336366F1), width: 1),
          boxShadow: [
            BoxShadow(
              color: isUser ? const Color(0x334F46E5) : const Color(0x22000000),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // AI Assistant Header with Avatar & Latency Badge
            if (!isUser) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF06B6D4)],
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.shield, color: Colors.white, size: 12),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Guardian AI',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  _buildEngineSourceBadge(msg),
                ],
              ),
              const SizedBox(height: 10),
            ],

            // Message Content
            Text(
              msg.text,
              style: TextStyle(
                color: isUser ? Colors.white : AppColors.textPrimary,
                fontSize: 13.5,
                height: 1.45,
                fontWeight: isUser ? FontWeight.w500 : FontWeight.w400,
              ),
            ),

            const SizedBox(height: 8),

            // Footer Action Row
            Row(
              mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.spaceBetween,
              children: [
                if (!isUser) ...[
                  // 🔊 "Listen in Guardian Male Voice" Action Button
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => voice.speakMessage(msg.id, msg.text),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isSpeaking ? AppColors.primary.withValues(alpha: 0.25) : Colors.white10,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSpeaking ? AppColors.primary : Colors.white12,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isSpeaking ? Icons.volume_up : Icons.volume_mute_outlined,
                            size: 14,
                            color: isSpeaking ? AppColors.primary : Colors.white70,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isSpeaking ? 'Playing Voice' : 'Listen',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isSpeaking ? AppColors.primary : Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 📋 Copy Button
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 14, color: Colors.white38),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Copy Message',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: msg.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Response copied to clipboard', style: TextStyle(fontSize: 12)),
                          duration: const Duration(seconds: 1),
                          backgroundColor: const Color(0xFF1F2937),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      );
                    },
                  ),
                ],

                // Timestamp with Checkmark
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${msg.timestamp.hour}:${msg.timestamp.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        color: isUser ? Colors.white70 : AppColors.textMuted,
                        fontSize: 10,
                      ),
                    ),
                    if (isUser) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.done_all_rounded, size: 13, color: Colors.white70),
                    ],
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEngineSourceBadge(ChatMessage msg) {
    final bool isReal = msg.responseSource.startsWith('REAL_');
    final bool isLocal = msg.responseSource == 'LOCAL_DETERMINISTIC';
    final bool isFallback = msg.fallbackDepth > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: isReal
            ? AppColors.primary.withValues(alpha: 0.15)
            : (isLocal ? AppColors.accentCyan.withValues(alpha: 0.15) : AppColors.statusReview.withValues(alpha: 0.15)),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isReal
              ? AppColors.primary.withValues(alpha: 0.35)
              : (isLocal ? AppColors.accentCyan.withValues(alpha: 0.35) : AppColors.statusReview.withValues(alpha: 0.35)),
        ),
      ),
      child: Text(
        isReal
            ? '✨ ${msg.modelUsed ?? "AI"} (${msg.latencyMs ?? 0}ms)${isFallback ? " 🔄" : ""}'
            : (isLocal ? '⚡ Verified Telemetry' : '🛡️ Rule-Based'),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: isReal
              ? AppColors.primary
              : (isLocal ? AppColors.accentCyan : AppColors.statusReview),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 🔮 REASONING THINKING INDICATOR
  // ---------------------------------------------------------------------------
  Widget _buildThinkingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF131A2B),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x336366F1)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            ),
            SizedBox(width: 12),
            Text(
              'Guardian is reasoning over live telemetry & permission data...',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 💡 QUICK SUGGESTION CHIPS ROW
  // ---------------------------------------------------------------------------
  Widget _buildSuggestionsRow(GuardianService guardian) {
    final suggestions = [
      'Microphone access today',
      'High-risk apps',
      'App usage foreground time',
      'Active network permissions',
    ];

    return Container(
      height: 38,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemCount: suggestions.length,
        itemBuilder: (context, idx) {
          final s = suggestions[idx];
          return ActionChip(
            label: Text(s, style: const TextStyle(fontSize: 11, color: Colors.white70)),
            backgroundColor: const Color(0xFF1F2937),
            side: const BorderSide(color: Color(0x226366F1)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onPressed: () => _sendMessage(guardian, s),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 🚀 ULTRA-MODERN FLOATING INPUT BAR
  // ---------------------------------------------------------------------------
  Widget _buildModernInputBar(GuardianService guardian, VoiceGuardianService voice) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF131A2B),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0x336366F1), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x44000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Suggestions trigger button
          IconButton(
            tooltip: 'Suggested Queries',
            icon: Icon(
              Icons.auto_awesome,
              size: 20,
              color: _showSuggestions ? AppColors.primary : Colors.white38,
            ),
            onPressed: () {
              setState(() => _showSuggestions = !_showSuggestions);
            },
          ),

          // Main text input
          Expanded(
            child: TextField(
              controller: _textController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'Ask about microphone, camera, risk...',
                hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
              onSubmitted: (val) => _sendMessage(guardian, val),
              onChanged: (_) => setState(() {}),
            ),
          ),

          // Direct Microphone Dictation Toggle
          IconButton(
            tooltip: 'Dictate with Voice',
            icon: Icon(
              voice.state == VoiceState.listening ? Icons.mic : Icons.mic_none,
              color: voice.state == VoiceState.listening ? AppColors.statusAttention : Colors.white60,
              size: 20,
            ),
            onPressed: () {
              if (voice.state == VoiceState.listening) {
                voice.stopListening();
              } else {
                setState(() => _isVoiceMode = true);
                voice.startListening();
              }
            },
          ),

          const SizedBox(width: 4),

          // Circular Gradient Send Button
          GestureDetector(
            onTap: _textController.text.trim().isNotEmpty
                ? () => _sendMessage(guardian, _textController.text)
                : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: _textController.text.trim().isNotEmpty
                    ? const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                      )
                    : const LinearGradient(
                        colors: [Color(0xFF1E293B), Color(0xFF1E293B)],
                      ),
                boxShadow: _textController.text.trim().isNotEmpty
                    ? const [
                        BoxShadow(
                          color: Color(0x556366F1),
                          blurRadius: 10,
                          offset: Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Icon(
                  Icons.arrow_upward_rounded,
                  color: _textController.text.trim().isNotEmpty ? Colors.white : Colors.white24,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 🎙️ VOICE GUARDIAN UI (Guardian Natural Voice Mode)
  // ---------------------------------------------------------------------------
  Widget _buildVoiceGuardianUI(VoiceGuardianService voice) {
    if (!voice.isVoiceAvailable && voice.errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.mic_off, size: 56, color: AppColors.statusReview),
              const SizedBox(height: 16),
              const Text(
                'Voice Hardware Service Notice',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                voice.errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => setState(() => _isVoiceMode = false),
                icon: const Icon(Icons.chat),
                label: const Text('Switch to Text Chat Mode'),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              ),
            ],
          ),
        ),
      );
    }

    final hasUserSpeech = voice.currentTranscript.isNotEmpty ||
        _messages.any((m) => m.isUser);
    final hasAiSpeech = voice.lastResponseText.isNotEmpty ||
        _messages.any((m) => !m.isUser && m.id != 'welcome');

    final latestUserText = voice.currentTranscript.isNotEmpty
        ? voice.currentTranscript
        : (_messages.where((m) => m.isUser).isNotEmpty
            ? _messages.where((m) => m.isUser).last.text
            : '');

    final latestAiText = voice.lastResponseText.isNotEmpty
        ? voice.lastResponseText
        : (_messages.where((m) => !m.isUser && m.id != 'welcome').isNotEmpty
            ? _messages.where((m) => !m.isUser && m.id != 'welcome').last.text
            : '');

    final currentTimeStr = DateFormat('h:mm a').format(DateTime.now());

    return Container(
      color: const Color(0xFF090A10),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            // Header Timestamp: "Today 9:37 AM"
            Text(
              'Today $currentTimeStr',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white54,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),

            // Active Male Voice Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x336366F1)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.record_voice_over, color: AppColors.primary, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    'Voice: ${voice.selectedVoiceName}',
                    style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Top Conversation Bubbles
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (hasUserSpeech && latestUserText.isNotEmpty)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          margin: const EdgeInsets.only(bottom: 20),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.78,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                            ),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Text(
                            latestUserText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ),
                    if (hasAiSpeech && latestAiText.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              latestAiText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                height: 1.45,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.copy, size: 16, color: Colors.white38),
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: latestAiText));
                                  },
                                  visualDensity: VisualDensity.compact,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.volume_up, size: 16, color: Colors.white38),
                                  onPressed: () => voice.speakMessage('voice_preview', latestAiText),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Center: Guardian Voice Orb (Luminous pulsating sphere)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GuardianVoiceOrb(
                    state: voice.state,
                    isVoiceAvailable: voice.isVoiceAvailable,
                    onTap: () {
                      if (voice.state == VoiceState.idle || voice.state == VoiceState.error) {
                        voice.startListening();
                      } else if (voice.state == VoiceState.listening) {
                        voice.stopListening();
                      } else if (voice.state == VoiceState.speaking) {
                        voice.interrupt();
                      }
                    },
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _getVoiceHintText(voice.state, voice),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // Bottom Bar: [+ Type] bar with mic, settings and [X] exit
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1C23),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  // [+ Type] Button
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => setState(() => _isVoiceMode = false),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, color: Colors.white70, size: 18),
                          SizedBox(width: 6),
                          Text(
                            'Type',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),

                  // Voice Settings Modal Trigger
                  IconButton(
                    icon: const Icon(Icons.tune_rounded, color: Colors.white70, size: 20),
                    onPressed: () => VoiceSettingsSheet.show(context),
                  ),

                  // Microphone mute/unmute toggle
                  IconButton(
                    icon: Icon(
                      voice.isMuted
                          ? Icons.mic_off
                          : (voice.state == VoiceState.listening ? Icons.mic : Icons.mic_none),
                      color: voice.isMuted ? Colors.redAccent : Colors.white70,
                      size: 22,
                    ),
                    onPressed: () => voice.toggleMute(),
                  ),

                  const SizedBox(width: 8),

                  // Circular Exit button [X]
                  GestureDetector(
                    onTap: () => setState(() => _isVoiceMode = false),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                      child: const Icon(Icons.close, color: Colors.black, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getVoiceHintText(VoiceState state, VoiceGuardianService voice) {
    switch (state) {
      case VoiceState.connecting:
        return 'Connecting live voice session...';
      case VoiceState.listening:
        return voice.currentTranscript.isNotEmpty
            ? '"${voice.currentTranscript}..."'
            : 'Listening... speak now';
      case VoiceState.thinking:
        return 'Thinking...';
      case VoiceState.speaking:
        return 'Speaking response... tap orb to interrupt';
      case VoiceState.interrupted:
        return 'Interrupted assistant. Listening...';
      case VoiceState.disconnected:
        return 'Live session disconnected. Tap orb to reconnect.';
      case VoiceState.error:
      case VoiceState.idle:
        return 'Tap orb to speak with Privacy Guardian';
    }
  }
}
