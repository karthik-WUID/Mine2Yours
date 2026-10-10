import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:file_selector/file_selector.dart';

import 'audio.dart';

Future<Map<String, dynamic>?> pickPersonnelImage({bool profile = false}) async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    final value = await AudioService.channel.invokeMethod(
      'pickPersonnelImage',
      {'kind': profile ? 'profile' : 'document'},
    );
    return value == null ? null : Map<String, dynamic>.from(value);
  }
  final file = await openFile(
    acceptedTypeGroups: [
      const XTypeGroup(
        label: 'Photos',
        extensions: ['jpg', 'jpeg', 'png'],
        mimeTypes: ['image/jpeg', 'image/png'],
        uniformTypeIdentifiers: ['public.jpeg', 'public.png'],
      ),
    ],
  );
  if (file == null) return null;
  if (await file.length() > 16 * 1024 * 1024) {
    throw Exception('Choose an image smaller than 16 MB.');
  }
  final bytes = await file.readAsBytes();
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: profile ? 512 : 1400,
    allowUpscaling: false,
  );
  final frame = await codec.getNextFrame();
  codec.dispose();
  var image = frame.image;
  final limit = (profile ? 256 : 1024) * 1024;
  try {
    for (var attempt = 0; attempt < 5; attempt++) {
      final result = await image.toByteData(format: ui.ImageByteFormat.png);
      if (result != null && result.lengthInBytes <= limit) {
        return {
          'base64': base64Encode(
            result.buffer.asUint8List(
              result.offsetInBytes,
              result.lengthInBytes,
            ),
          ),
          'mimeType': 'image/png',
        };
      }
      final width = (image.width * .7).round(),
          height = (image.height * .7).round();
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImageRect(
        image,
        ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        ui.Paint(),
      );
      final picture = recorder.endRecording();
      final scaled = await picture.toImage(width, height);
      picture.dispose();
      image.dispose();
      image = scaled;
    }
    throw Exception('This photo could not be resized. Choose a smaller image.');
  } finally {
    image.dispose();
  }
}
