import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'design.dart';

class TeamBackdrop extends StatelessWidget {
  final Widget child;
  const TeamBackdrop({super.key, required this.child});
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xffb5efff),
          Color(0xffe9fbff),
          Color(0xfff8ffda),
          Color(0xffbceca1),
        ],
      ),
    ),
    child: CustomPaint(painter: _Waves(), child: child),
  );
}

class _Waves extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    for (final entry in [
      (const Color(0xff3ad7e8), .88),
      (const Color(0xffffdf55), .97),
      (const Color(0xff74e5ae), 1.04),
    ]) {
      final y = size.height * entry.$2;
      final p = Path()
        ..moveTo(0, y)
        ..cubicTo(
          size.width * .34,
          y + 95,
          size.width * .7,
          y - 110,
          size.width,
          y - 40,
        )
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(p, Paint()..color = entry.$1.withValues(alpha: .38));
    }
  }

  @override
  bool shouldRepaint(_Waves oldDelegate) => false;
}

class TeamHero extends StatelessWidget {
  final String? name;
  const TeamHero({super.key, this.name});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        name == null ? 'Speak to your team' : 'Speak to $name',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 21),
      ),
      const SizedBox(height: 4),
      Text(
        name == null
            ? 'Choose a person below to start.'
            : 'Speak, check your words, then send.',
        style: const TextStyle(color: muted, fontSize: 13),
      ),
    ],
  );
}

class SpeakButton extends StatelessWidget {
  final String label;
  final bool recording, working;
  final VoidCallback? onPressed;
  final ValueListenable<double>? level;
  const SpeakButton({
    super.key,
    required this.label,
    this.recording = false,
    this.working = false,
    this.onPressed,
    this.level,
  });
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: recording
            ? [const Color(0xffef745e), const Color(0xffc33540)]
            : [
                const Color(0xff04c8ee),
                const Color(0xff0070f5),
                const Color(0xff00ccdd),
              ],
      ),
      boxShadow: [
        BoxShadow(
          color: blue.withValues(alpha: .22),
          blurRadius: 18,
          offset: const Offset(0, 7),
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: .15),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .3),
                    width: 2,
                  ),
                ),
                child: working
                    ? const SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Icon(
                        recording ? Icons.stop_rounded : Icons.mic_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(color: Colors.white, fontSize: 17),
                    ),
                    const SizedBox(height: 10),
                    VoiceEqualizer(active: recording, level: level),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class VoiceEqualizer extends StatefulWidget {
  final bool active;
  final ValueListenable<double>? level;
  const VoiceEqualizer({super.key, this.active = false, this.level});
  @override
  State<VoiceEqualizer> createState() => _VoiceEqualizerState();
}

class _VoiceEqualizerState extends State<VoiceEqualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  @override
  void initState() {
    super.initState();
    if (widget.active) _clock.repeat();
  }

  @override
  void didUpdateWidget(VoiceEqualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_clock.isAnimating) _clock.repeat();
    if (!widget.active) _clock.stop();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _clock,
    builder: (context, _) => widget.level == null
        ? _bars(0)
        : ValueListenableBuilder<double>(
            valueListenable: widget.level!,
            builder: (_, value, _) => _bars(value),
          ),
  );
  Widget _bars(double level) => Semantics(
    label: widget.active ? 'Microphone level' : 'Microphone idle',
    child: SizedBox(
      height: 28,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(12, (i) {
          final motion =
              .45 + .55 * math.sin(_clock.value * math.pi * 2 + i * .8).abs();
          final height = widget.active
              ? 4 + 24 * level.clamp(0, 1) * motion
              : 4.0;
          return Container(
            key: ValueKey('voice-bar-$i'),
            width: 4,
            height: height,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    ),
  );
}
