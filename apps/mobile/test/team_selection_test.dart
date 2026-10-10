import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mine2yourlingo/core/app_controller.dart';
import 'package:mine2yourlingo/core/design.dart';
import 'package:mine2yourlingo/features/groups/team_home_screen.dart';
import 'package:mine2yourlingo/features/personnel/personnel_screen.dart';

import 'layout_test.dart' show fixture;
import 'widget_test.dart' show TestController;

void main() {
  testWidgets(
    'member microphone selects only that member before opening speech',
    (tester) async {
      final controller = TestController(fixture);
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, _) => const Scaffold(body: TeamHomeScreen()),
          ),
          GoRoute(
            path: '/speak',
            builder: (_, _) =>
                const Scaffold(body: Text('Selected conversation')),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appProvider.overrideWith(() => controller)],
          child: MaterialApp.router(theme: appTheme(), routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      final microphone = find.widgetWithIcon(IconButton, Icons.mic_rounded);
      await tester.ensureVisible(microphone);
      await tester.pumpAndSettle();
      await tester.tap(microphone);
      await tester.pumpAndSettle();
      expect(controller.snapshot.recipientId, 'worker');
      expect(controller.snapshot.selectedGroupId, 'g');
      expect(find.text('Selected conversation'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    },
  );
  testWidgets(
    'personnel screen exposes no salary editor to ordinary team members',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appProvider.overrideWith(() => TestController(fixture))],
          child: MaterialApp(
            theme: appTheme(),
            home: const Scaffold(body: PersonnelScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Team admins only'), findsOneWidget);
      expect(find.text('Add member record'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
