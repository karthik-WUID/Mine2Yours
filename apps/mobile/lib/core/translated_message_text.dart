import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'audio.dart';
import 'design.dart';

class TranslatedMessageText extends StatefulWidget {
  final AppController app;
  final Json message, translation;
  const TranslatedMessageText({
    super.key,
    required this.app,
    required this.message,
    required this.translation,
  });
  @override
  State<TranslatedMessageText> createState() => _TranslatedMessageTextState();
}

class _TranslatedMessageTextState extends State<TranslatedMessageText> {
  late Future<String> _text;
  void _load() {
    _text = widget.app.translationText(widget.message, widget.translation);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(TranslatedMessageText old) {
    super.didUpdateWidget(old);
    if (old.message['id'] != widget.message['id'] ||
        old.translation['language'] != widget.translation['language'] ||
        old.translation['text'] != widget.translation['text']) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _text,
    builder: (_, snapshot) {
      if (snapshot.hasError) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AudioService.describeError(snapshot.error!),
              style: const TextStyle(color: muted, fontSize: 12),
            ),
            TextButton(
              onPressed: () => setState(_load),
              child: const Text('Translate with Google'),
            ),
          ],
        );
      }
      if (!snapshot.hasData) {
        return const Text(
          'Preparing free device translation… The first download needs an internet connection.',
          style: TextStyle(color: muted, fontSize: 12),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(snapshot.data!),
          if (widget.translation['needsDeviceTranslation'] == true)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: InkWell(
                onTap: () => AudioService.channel.invokeMethod(
                  'openTranslationAttribution',
                ),
                child: Semantics(
                  label: 'Powered by Google Translate',
                  child: Image.asset(
                    'assets/google-translate-attribution.png',
                    height: 16,
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
