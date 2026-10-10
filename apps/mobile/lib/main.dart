import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/app_controller.dart';
import 'core/design.dart';
import 'core/shell.dart';
import 'features/auth/welcome_screen.dart';
import 'features/communication/home_screen.dart';
import 'features/groups/groups_screen.dart';
import 'features/groups/team_home_screen.dart';
import 'features/settings/languages_screen.dart';
import 'features/personnel/personnel_screen.dart';
import 'features/history/history_screen.dart';
import 'features/phrases/phrases_screen.dart';
import 'features/settings/settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final family in [
      'Inter',
      'NotoSansTamil',
      'NotoSansBengali',
      'NotoSansDevanagari',
      'NotoSansOdia',
      'NotoSansTelugu',
      'NotoSansKannada',
      'NotoSansMalayalam',
      'NotoSansGujarati',
      'NotoSansGurmukhi',
      'NotoNaskhArabic',
      'NotoSansMeeteiMayek',
      'NotoSansOlChiki',
    ]) {
      yield LicenseEntryWithLineBreaks([
        family,
      ], await rootBundle.loadString('assets/fonts/$family-OFL.txt'));
    }
  });
  runApp(const ProviderScope(child: Mine2YourLingoApp()));
}

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final app = ref.read(appProvider);
      if (app.loading) return state.uri.path == '/' ? null : '/';
      if (app.user == null) {
        return state.uri.path == '/welcome' ? null : '/welcome';
      }
      if (state.uri.path == '/' || state.uri.path == '/welcome') return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Brand(width: 250),
                SizedBox(height: 24),
                CircularProgressIndicator(strokeWidth: 2),
              ],
            ),
          ),
        ),
      ),
      GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(path: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/speak',
            builder: (_, s) => HomeScreen(
              autoRecord: s.uri.queryParameters['record'] == 'true',
            ),
          ),
          GoRoute(path: '/history', builder: (_, _) => const HistoryScreen()),
          GoRoute(path: '/phrases', builder: (_, _) => const PhrasesScreen()),
          GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
          GoRoute(
            path: '/team',
            builder: (_, _) => const TeamHomeScreen(directory: true),
          ),
          GoRoute(
            path: '/manage-teams',
            builder: (_, _) => const GroupsScreen(),
          ),
          GoRoute(
            path: '/personnel',
            builder: (_, _) => const PersonnelScreen(),
          ),
          GoRoute(
            path: '/languages',
            builder: (_, _) => const LanguagesScreen(),
          ),
          GoRoute(
            path: '/group/:id',
            builder: (_, s) => GroupDetailScreen(id: s.pathParameters['id']!),
          ),
          GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
        ],
      ),
    ],
  );
  ref.listen(appProvider, (previous, next) {
    if (previous?.loading != next.loading ||
        previous?.user?['id'] != next.user?['id']) {
      router.refresh();
    }
  });
  ref.onDispose(router.dispose);
  return router;
});

class Mine2YourLingoApp extends ConsumerWidget {
  const Mine2YourLingoApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'Mine2YourLingo',
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    routerConfig: ref.watch(routerProvider),
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [
      Locale('en'),
      Locale('ta'),
      Locale('bn'),
      Locale('hi'),
      Locale('or'),
    ],
  );
}
