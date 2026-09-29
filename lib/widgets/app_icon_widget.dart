import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_colors.dart';

/// Performance-optimized widget for rendering native Android application icons
/// loaded via MethodChannel and cached in memory.
class AppIconWidget extends StatefulWidget {
  final String packageName;
  final String appName;
  final double size;
  final double borderRadius;

  const AppIconWidget({
    super.key,
    required this.packageName,
    required this.appName,
    this.size = 44,
    this.borderRadius = 10,
  });

  // Global in-memory cache to prevent redundant IPC calls across screens and list items
  static final Map<String, Uint8List?> _iconCache = {};

  @override
  State<AppIconWidget> createState() => _AppIconWidgetState();
}

class _AppIconWidgetState extends State<AppIconWidget> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _loadIcon();
  }

  @override
  void didUpdateWidget(AppIconWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.packageName != widget.packageName) {
      _loadIcon();
    }
  }

  Future<void> _loadIcon() async {
    if (widget.packageName.isEmpty) return;

    if (AppIconWidget._iconCache.containsKey(widget.packageName)) {
      if (mounted) {
        setState(() {
          _bytes = AppIconWidget._iconCache[widget.packageName];
        });
      }
      return;
    }

    try {
      const channel = MethodChannel('privacy_sentinel');
      final Uint8List? bytes = await channel.invokeMethod<Uint8List>(
        'getAppIcon',
        {'packageName': widget.packageName},
      );
      AppIconWidget._iconCache[widget.packageName] = bytes;
      if (mounted) {
        setState(() {
          _bytes = bytes;
        });
      }
    } catch (_) {
      AppIconWidget._iconCache[widget.packageName] = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes != null && _bytes!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: Image.memory(
          _bytes!,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) => _buildFallbackAvatar(),
        ),
      );
    }

    return _buildFallbackAvatar();
  }

  Widget _buildFallbackAvatar() {
    final initial = widget.appName.isNotEmpty ? widget.appName[0].toUpperCase() : 'A';
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: widget.size * 0.42,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}
