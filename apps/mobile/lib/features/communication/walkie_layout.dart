import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_controller.dart';
import '../../core/design.dart';
import '../../core/languages.dart';
import '../../core/team_theme.dart';
import '../groups/team_home_screen.dart';

/// Live controls corresponding to the supplied communication mockup.
class WalkieLayout extends StatelessWidget {
  final AppState state;
  final AppController app;
  final bool recording, working, walkie;
  final String transcript;
  final VoidCallback onTap,
      onCancel,
      onManage,
      onSettings,
      onHistory,
      onLanguages;
  final GestureLongPressStartCallback? onHold;
  final GestureLongPressEndCallback? onRelease;
  final VoidCallback? onHoldCancel;
  final ValueChanged<bool> onWalkie, onSpeaker;
  const WalkieLayout({
    super.key,
    required this.state,
    required this.app,
    required this.recording,
    required this.working,
    required this.walkie,
    required this.transcript,
    required this.onTap,
    required this.onCancel,
    required this.onManage,
    required this.onSettings,
    required this.onHistory,
    required this.onLanguages,
    required this.onHold,
    required this.onRelease,
    required this.onHoldCancel,
    required this.onWalkie,
    required this.onSpeaker,
  });
  bool get busy => recording || working;
  List<Json> get others =>
      state.members.where((m) => m['userId'] != state.user?['id']).toList();
  String? get targetLanguage {
    if (state.recipient != null) {
      return state.recipient!['listeningLanguage'] ??
          state.recipient!['spokenLanguage'];
    }
    final languages = others
        .map((m) => m['listeningLanguage'] ?? m['spokenLanguage'])
        .whereType<String>()
        .toSet();
    return languages.length == 1 ? languages.first : null;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final largeText = MediaQuery.textScalerOf(context).scale(14) > 19;
      Widget content(double height) => SizedBox(
        height: height,
        child: bounds.maxWidth >= 750 && height < 600 && !largeText
            ? Row(
                children: [
                  SizedBox(
                    width: 350,
                    child: Column(
                      children: [
                        _teamPanel(context),
                        const SizedBox(height: 12),
                        _languages(context),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(child: _talkZone(context)),
                        _controls(context),
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  _teamPanel(context),
                  const SizedBox(height: 10),
                  _languages(context),
                  const SizedBox(height: 6),
                  Expanded(child: _talkZone(context)),
                  _controls(context),
                ],
              ),
      );
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: largeText || bounds.maxHeight < 420
                ? SingleChildScrollView(
                    child: content(math.max(930, bounds.maxHeight - 10)),
                  )
                : content(bounds.maxHeight - 10),
          ),
        ),
      );
    },
  );
  Widget _teamPanel(BuildContext context) => Surface(
    padding: const EdgeInsets.all(12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.groups_rounded, color: blue, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (state.groups.isNotEmpty)
                    SizedBox(
                      height: 34,
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: state.group?['id'],
                          isExpanded: true,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            color: navy,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                          items: state.groups
                              .map(
                                (g) => DropdownMenuItem<String>(
                                  value: g['id'],
                                  child: Text(
                                    g['name'],
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: busy
                              ? null
                              : (id) {
                                  if (id != null) app.selectGroup(id);
                                },
                        ),
                      ),
                    )
                  else
                    const Text(
                      'Choose your team',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  Text(
                    '${state.members.length} members · Team channel',
                    style: const TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Manage team',
              onPressed: busy ? null : onManage,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: MediaQuery.textScalerOf(context).scale(14) > 19 ? 112 : 72,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _memberCard(context, null),
              ...others.map((m) => _memberCard(context, m)),
              SizedBox(
                width:
                    others.length <= 1 && MediaQuery.sizeOf(context).width < 600
                    ? 54
                    : 78,
                child: OutlinedButton(
                  onPressed: busy ? null : onManage,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(6),
                    side: const BorderSide(color: border),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_rounded, size: 25),
                      Text('Add', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _memberCard(BuildContext context, Json? member) {
    final selected = state.recipientId == member?['userId'];
    final name = member == null
        ? 'Everyone'
        : memberDisplayName(member['displayName']);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SizedBox(
        width: others.length <= 1 && MediaQuery.sizeOf(context).width < 600
            ? ((MediaQuery.sizeOf(context).width - 122) / 2).clamp(128, 210)
            : 174,
        child: Material(
          color: selected ? const Color(0xffe4f6ff) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: selected ? blue : border,
              width: selected ? 1.7 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: busy ? null : () => app.selectRecipient(member?['userId']),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  if (member != null)
                    MemberAvatar(member: member, radius: 18)
                  else
                    const CircleAvatar(
                      radius: 18,
                      backgroundColor: Color(0xffcceaff),
                      child: Icon(Icons.groups_rounded, color: blue, size: 24),
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          member == null
                              ? 'Team members'
                              : AppLanguage.of(member['listeningLanguage'])
                                    .name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: muted, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _languages(BuildContext context) => Surface(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    child: Row(
      children: [
        Expanded(
          child: _languagePill(
            'I speak',
            AppLanguage.of(state.language),
            true,
            onLanguages,
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Icon(Icons.swap_horiz_rounded, color: blue, size: 25),
        ),
        Expanded(
          child: _languagePill(
            'They hear',
            targetLanguage == null ? null : AppLanguage.of(targetLanguage),
            false,
            () => _receiverLanguages(context),
          ),
        ),
      ],
    ),
  );
  Widget _languagePill(
    String label,
    AppLanguage? language,
    bool source,
    VoidCallback action,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(color: muted, fontSize: 11),
      ),
      const SizedBox(height: 5),
      Material(
        color: source ? const Color(0xffe1f4ff) : const Color(0xffe1fbea),
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: busy ? null : action,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: source ? blue : teal,
                  child: Icon(
                    source ? Icons.mic_none_rounded : Icons.volume_up_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        language?.nativeName ?? 'Each person',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        language?.name ?? 'Their language',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: muted),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.expand_more_rounded, size: 18),
              ],
            ),
          ),
        ),
      ),
    ],
  );
  void _receiverLanguages(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'They hear',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                'Each team member chooses their listening language on their own device.',
                style: TextStyle(color: muted, fontSize: 13),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children:
                      (state.recipient == null ? others : [state.recipient!])
                          .map(
                            (m) => ListTile(
                              leading: MemberAvatar(member: m, radius: 19),
                              title: Text(memberDisplayName(m['displayName'])),
                              subtitle: Text(
                                AppLanguage.of(
                                  m['listeningLanguage'] ?? m['spokenLanguage'],
                                ).name,
                              ),
                            ),
                          )
                          .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _talkZone(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final size = math
          .min(bounds.maxWidth * .76, bounds.maxHeight - (recording ? 103 : 71))
          .clamp(74.0, 370.0);
      return ClipRect(
        child: CustomPaint(
          painter: const WalkieScenePainter(),
          child: SizedBox.expand(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onLongPressStart: working ? null : onHold,
                  onLongPressEnd: onRelease,
                  onLongPressCancel: onHoldCancel,
                  child: Semantics(
                    label: recording
                        ? 'Stop recording and send'
                        : 'Hold or tap to start a voice message',
                    button: true,
                    child: Container(
                      width: size,
                      height: size,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xff80f2fc),
                        boxShadow: [
                          BoxShadow(
                            color: blue.withValues(alpha: .2),
                            blurRadius: 22,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Material(
                        color: blue,
                        shape: const CircleBorder(),
                        child: Ink(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xff05d6fa),
                              width: 3,
                            ),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xff00d0ef),
                                Color(0xff0077fb),
                                Color(0xff0047c8),
                              ],
                            ),
                          ),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: working ? null : onTap,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (working)
                                  const SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                else
                                  Icon(
                                    recording
                                        ? Icons.stop_rounded
                                        : Icons.mic_rounded,
                                    color: Colors.white,
                                    size: (size * .31).clamp(34, 92),
                                  ),
                                if (size >= 135) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    recording
                                        ? 'LISTENING'
                                        : walkie
                                        ? 'HOLD TO TALK'
                                        : 'TAP TO TALK',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: size > 250 ? 17 : 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  VoiceEqualizer(
                                    active: recording,
                                    level: app.audio.inputLevel,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  state.activeSpeakerId != null
                      ? 'Speaking: ${state.activeSpeakerName}'
                      : recording
                      ? 'Listening…'
                      : 'Ready to talk to ${state.recipient == null ? 'Everyone' : memberDisplayName(state.recipient!['displayName'])}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                if (recording && transcript.isNotEmpty)
                  SizedBox(
                    height: 22,
                    child: SingleChildScrollView(
                      child: Text(
                        transcript,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  )
                else
                  Text(
                    recording
                        ? 'Release or tap to translate & send'
                        : walkie
                        ? 'Hold to speak · Release to translate & send'
                        : 'Tap to speak · Tap again to translate & send',
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                if (recording)
                  SizedBox(
                    height: 30,
                    child: TextButton(
                      onPressed: onCancel,
                      child: const Text('Cancel recording'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
  Widget _controls(BuildContext context) => SizedBox(
    height: MediaQuery.textScalerOf(context).scale(14) > 19 ? 76 : 57,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _roundControl(
          'Read replies aloud',
          state.receiving && state.receiveMode == 'automatic'
              ? Icons.volume_up_rounded
              : Icons.volume_off_rounded,
          state.receiving && state.receiveMode == 'automatic'
              ? 'Mute'
              : 'Unmute',
          () =>
              onSpeaker(!(state.receiving && state.receiveMode == 'automatic')),
        ),
        Text(
          walkie ? 'Hold to talk' : 'Tap to talk',
          style: const TextStyle(fontSize: 11, color: muted),
        ),
        _roundControl(
          'More voice options',
          Icons.tune_rounded,
          'More',
          () => _more(context),
        ),
      ],
    ),
  );
  Widget _roundControl(
    String tooltip,
    IconData icon,
    String label,
    VoidCallback action,
  ) => Column(
    children: [
      SizedBox(
        height: 36,
        child: IconButton.filledTonal(
          tooltip: tooltip,
          onPressed: busy ? null : action,
          style: IconButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: navy,
            padding: const EdgeInsets.all(7),
          ),
          icon: Icon(icon, size: 23),
        ),
      ),
      const SizedBox(height: 3),
      Text(
        label,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
      ),
    ],
  );
  void _more(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            title: const Text('Hold to talk'),
            subtitle: const Text(
              'Turn off to tap once to start and again to send.',
            ),
            value: walkie,
            onChanged: (v) {
              onWalkie(v);
              Navigator.pop(ctx);
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings_rounded),
            title: const Text('Settings'),
            onTap: () {
              Navigator.pop(ctx);
              onSettings();
            },
          ),
          const SizedBox(height: 10),
        ],
      ),
    ),
  );
}

/// Decorative vector radios and concentric rings; no prerecorded waveform data.
class WalkieScenePainter extends CustomPainter {
  const WalkieScenePainter();
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (final radius in [.33, .44, .55, .68]) {
      canvas.drawCircle(
        center,
        math.min(size.width, size.height) * radius,
        Paint()..color = const Color(0xff1abaf3).withValues(alpha: .035),
      );
    }
    if (size.height < 200 || size.width < 300) return;
    for (final left in [true, false]) {
      canvas.save();
      canvas.translate(left ? -23 : size.width + 23, size.height * .58);
      canvas.rotate(left ? .23 : -.23);
      final body = Rect.fromLTWH(-44, -55, 88, 158);
      final antenna = RRect.fromRectAndRadius(
        const Rect.fromLTWH(-8, -126, 21, 87),
        const Radius.circular(9),
      );
      canvas.drawRRect(antenna, Paint()..color = const Color(0xff435571));
      canvas.drawRRect(
        RRect.fromRectAndRadius(body, const Radius.circular(23)),
        Paint()
          ..color = left ? const Color(0xff0088ff) : const Color(0xffffca2b),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(body.deflate(8), const Radius.circular(17)),
        Paint()..color = const Color(0xff354b63),
      );
      for (var i = 0; i < 6; i++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(-25, -32 + i * 12, 49, 5),
            const Radius.circular(3),
          ),
          Paint()..color = const Color(0xff1b2b42),
        );
      }
      canvas.drawCircle(
        const Offset(0, 68),
        16,
        Paint()
          ..color = left ? const Color(0xff00befa) : const Color(0xffffb000),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(WalkieScenePainter oldDelegate) => false;
}
