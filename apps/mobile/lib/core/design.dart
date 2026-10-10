import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'languages.dart';
import 'audio.dart';

const navy = Color(0xff09254c);
const blue = Color(0xff0069f5);
const teal = Color(0xff19a854);
const canvas = Color(0xffeefaff);
const muted = Color(0xff596475);
const border = Color(0xffdee3e9);

ThemeData appTheme() => ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: canvas,
  colorScheme: ColorScheme.fromSeed(
    seedColor: blue,
    primary: blue,
    secondary: teal,
    surface: Colors.white,
    onSurface: navy,
  ),
  fontFamily: 'Inter',
  fontFamilyFallback: const [
    'NotoSansTamil',
    'NotoSansBengali',
    'NotoSansDevanagari',
    'NotoSansOdia',
    'NotoSansOlChiki',
    'NotoSansMeeteiMayek',
    'NotoNaskhArabic',
    'NotoSansGurmukhi',
    'NotoSansGujarati',
    'NotoSansMalayalam',
    'NotoSansKannada',
    'NotoSansTelugu',
  ],
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      color: navy,
      letterSpacing: -0.5,
    ),
    headlineMedium: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      color: navy,
      letterSpacing: -0.6,
    ),
    titleLarge: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: navy,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: navy,
    ),
    bodyLarge: TextStyle(fontSize: 14, color: navy, height: 1.5),
    bodyMedium: TextStyle(fontSize: 14, color: navy, height: 1.45),
    bodySmall: TextStyle(fontSize: 12, color: muted, height: 1.45),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: canvas,
    foregroundColor: navy,
    centerTitle: false,
    elevation: 0,
  ),
  navigationBarTheme: NavigationBarThemeData(
    labelTextStyle: WidgetStateProperty.resolveWith(
      (states) => TextStyle(
        fontFamily: 'Inter',
        fontFamilyFallback: const [
          'NotoSansTamil',
          'NotoSansBengali',
          'NotoSansDevanagari',
          'NotoSansOdia',
        ],
        fontSize: 12,
        fontWeight: states.contains(WidgetState.selected)
            ? FontWeight.w700
            : FontWeight.w500,
        color: states.contains(WidgetState.selected) ? blue : muted,
      ),
    ),
  ),
  dividerTheme: const DividerThemeData(color: border, thickness: 1),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0xfff7f9fc),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: blue, width: 1.5),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(48, 52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      textStyle: const TextStyle(
        fontFamily: 'Inter',
        fontFamilyFallback: [
          'NotoSansTamil',
          'NotoSansBengali',
          'NotoSansDevanagari',
          'NotoSansOdia',
          'NotoSansOlChiki',
          'NotoSansMeeteiMayek',
          'NotoNaskhArabic',
          'NotoSansGurmukhi',
          'NotoSansGujarati',
          'NotoSansMalayalam',
          'NotoSansKannada',
          'NotoSansTelugu',
        ],
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
      side: const BorderSide(color: border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
  ),
  cardTheme: CardThemeData(
    color: Colors.white,
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(26),
      side: const BorderSide(color: border),
    ),
  ),
  snackBarTheme: SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    backgroundColor: navy,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
  ),
);

class Brand extends StatelessWidget {
  final double width;
  const Brand({super.key, this.width = 175});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Mine2YourLingo. My Voice. Your Language.',
    child: SizedBox(
      width: width,
      height: width * 0.36,
      child: Image.asset(
        'assets/logo-universal.png',
        width: width,
        height: width * 0.36,
        fit: BoxFit.contain,
      ),
    ),
  );
}

class Surface extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: color ?? Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(26),
      side: const BorderSide(color: Color(0xffeef4fa)),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class Tag extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const Tag(this.text, {super.key, this.color = teal, this.icon});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class InitialAvatar extends StatelessWidget {
  final String name;
  final double radius;
  final Color color;
  const InitialAvatar(
    this.name, {
    super.key,
    this.radius = 23,
    this.color = blue,
  });
  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: radius,
    backgroundColor: color.withValues(alpha: 0.10),
    child: Text(
      name.trim().isEmpty
          ? '?'
          : name
                .trim()
                .split(RegExp(r'\s+'))
                .take(2)
                .map((e) => e.characters.first)
                .join()
                .toUpperCase(),
      style: TextStyle(
        color: color,
        fontWeight: FontWeight.w700,
        fontSize: radius * 0.62,
      ),
    ),
  );
}

class LanguageSelect extends StatelessWidget {
  final String value, label;
  final ValueChanged<String> onChanged;
  const LanguageSelect({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: value,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: const Icon(Icons.translate_rounded, size: 21),
    ),
    isExpanded: true,
    items: AppLanguage.all
        .map(
          (l) => DropdownMenuItem(
            value: l.code,
            child: Text(
              '${l.name} · ${l.nativeName}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList(),
    onChanged: (v) {
      if (v != null) onChanged(v);
    },
  );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, description;
  final Widget? action;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 12),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(19),
          decoration: BoxDecoration(
            color: blue.withValues(alpha: 0.06),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: blue, size: 32),
        ),
        const SizedBox(height: 18),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 7),
        Text(
          description,
          style: const TextStyle(color: muted, fontSize: 14),
          textAlign: TextAlign.center,
        ),
        if (action != null) ...[const SizedBox(height: 20), action!],
      ],
    ),
  );
}

void notice(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<void> runAction(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  try {
    await action();
    if (context.mounted && success != null) notice(context, success);
  } catch (e) {
    if (context.mounted) {
      notice(context, AudioService.describeError(e));
    }
  }
}

Future<String?> askText(
  BuildContext context, {
  required String title,
  String hint = '',
  String initial = '',
  String action = 'Save',
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        maxLength: 150,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (controller.text.trim().isNotEmpty) {
              Navigator.pop(ctx, controller.text.trim());
            }
          },
          child: Text(action),
        ),
      ],
    ),
  );
  // Controller may still be attached during the route's exit animation.
  Future.delayed(const Duration(milliseconds: 300), controller.dispose);
  return result;
}

Future<bool> confirmAction(
  BuildContext context,
  String title,
  String body, {
  String action = 'Confirm',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;
Future<void> copyText(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) notice(context, 'Copied to clipboard.');
}
