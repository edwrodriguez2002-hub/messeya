import 'dart:ui';

import 'package:flutter/material.dart';

class MesseyaUi {
  static const background = Color(0xFF081225);
  static const backgroundTop = Color(0xFF0D1830);
  static const card = Color(0xCC101B37);
  static const cardSoft = Color(0xB3152343);
  static const cardOutline = Color(0x1FFFFFFF);
  static const accent = Color(0xFF42A5FF);
  static const accentSoft = Color(0xFF7BC2FF);
  static const success = Color(0xFF4DD890);
  static const danger = Color(0xFFFF6D8F);
  static const textMuted = Color(0xFF8D96B5);
}

class MesseyaBackground extends StatelessWidget {
  const MesseyaBackground({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            MesseyaUi.backgroundTop,
            MesseyaUi.background,
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: -120,
            right: -80,
            child: _GlowOrb(
              size: 260,
              color: MesseyaUi.accent.withValues(alpha: 0.08),
            ),
          ),
          Positioned(
            top: 240,
            left: -90,
            child: _GlowOrb(
              size: 220,
              color: const Color(0xFF8F5FFF).withValues(alpha: 0.05),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: _NoisePainter(),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class MesseyaPanel extends StatelessWidget {
  const MesseyaPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16), // REDUCIDO DE 20
    this.margin,
    this.borderRadius = 24, // REDUCIDO DE 28
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: MesseyaUi.card,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: MesseyaUi.cardOutline),
        boxShadow: const [
          BoxShadow(
            color: Color(0x44000000),
            blurRadius: 24, // REDUCIDO DE 32
            offset: Offset(0, 12), // REDUCIDO DE 20
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

class MesseyaTopBar extends StatelessWidget {
  const MesseyaTopBar({
    super.key,
    required this.title,
    this.actions = const [],
    this.subtitle,
  });

  final String title;
  final List<Widget> actions;
  final Widget? subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith( // CAMBIADO DE headlineLarge
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 8), // REDUCIDO DE 10
                subtitle!,
              ],
            ],
          ),
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(width: 12), // REDUCIDO DE 16
          Row(children: actions),
        ],
      ],
    );
  }
}

class MesseyaRoundIconButton extends StatelessWidget {
  const MesseyaRoundIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    Widget button = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20), // REDUCIDO DE 24
      child: Ink(
        width: 48, // REDUCIDO DE 58
        height: 48, // REDUCIDO DE 58
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
        ),
        child: Icon(icon, color: Colors.white, size: 24), // REDUCIDO DE 28
      ),
    );

    if (tooltip != null) {
      button = Tooltip(
        message: tooltip!,
        child: button,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(left: 10), // REDUCIDO DE 12
      child: button,
    );
  }
}

class MesseyaSearchField extends StatelessWidget {
  const MesseyaSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white, fontSize: 16), // REDUCIDO DE 18
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(
          color: MesseyaUi.textMuted,
          fontSize: 16, // REDUCIDO DE 18
        ),
        prefixIcon:
            const Icon(Icons.search_rounded, color: MesseyaUi.textMuted, size: 22), // AÑADIDO SIZE
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.04),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), // AJUSTADO
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22), // REDUCIDO DE 26
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: MesseyaUi.accentSoft, width: 1.2),
        ),
      ),
    );
  }
}

class MesseyaSectionLabel extends StatelessWidget {
  const MesseyaSectionLabel(this.label, {super.key, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith( // CAMBIADO DE titleLarge
                  color: MesseyaUi.textMuted,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class MesseyaPillButton extends StatelessWidget {
  const MesseyaPillButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.filled = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), // REDUCIDO
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: filled
              ? const LinearGradient(
                  colors: [Color(0xFF65BEFF), Color(0xFF2D7EEB)],
                )
              : null,
          color: filled ? null : Colors.white.withValues(alpha: 0.08),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white, size: 16), // REDUCIDO DE 18
              const SizedBox(width: 6), // REDUCIDO DE 8
            ],
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13, // AÑADIDO
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color,
              blurRadius: 90,
              spreadRadius: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoisePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.014)
      ..strokeWidth = 1;
    for (double y = 0; y < size.height; y += 18) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y + 8), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
