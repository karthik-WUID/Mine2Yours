import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine2yourlingo/core/app_controller.dart';
import 'package:mine2yourlingo/core/design.dart';
import 'package:mine2yourlingo/core/shell.dart';
import 'package:mine2yourlingo/features/auth/welcome_screen.dart';
import 'package:mine2yourlingo/features/communication/home_screen.dart';
import 'package:mine2yourlingo/features/groups/team_home_screen.dart';

import 'widget_test.dart' show TestController;

const fixture = AppState(
  loading: false,
  connected: true,
  receiving: true,
  receiveMode: 'automatic',
  user: {
    'id': 'engineer',
    'displayName': 'Karthik',
    'spokenLanguage': 'ta',
    'listeningLanguage': 'ta',
  },
  selectedGroupId: 'g',
  groups: [
    {
      'id': 'g',
      'name': 'Green Valley Team',
      'members': [
        {
          'userId': 'engineer',
          'displayName': 'Karthik',
          'spokenLanguage': 'ta',
          'listeningLanguage': 'ta',
          'role': 'admin',
        },
        {
          'userId': 'worker',
          'displayName': 'Rahim',
          'spokenLanguage': 'bn',
          'listeningLanguage': 'bn',
          'role': 'member',
        },
      ],
    },
  ],
);
void main() {
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
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
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/$family.ttf'))).load();
    }
  });
  for (final size in [const Size(390, 844), const Size(1440, 960)]) {
    testWidgets('home has no layout exceptions at ${size.width.toInt()}px', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appProvider.overrideWith(() => TestController(fixture))],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: appTheme(),
            home: const AppShell(path: '/home', child: HomeScreen()),
          ),
        ),
      );
      await tester.runAsync(() async {
        for (final asset in [
          'assets/logo-universal.png',
          'assets/team-hero.png',
        ]) {
          await precacheImage(
            AssetImage(asset),
            tester.element(find.byType(MaterialApp)),
          );
        }
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      if (size.width == 390) {
        for (final scrollable in tester.stateList<ScrollableState>(
          find.byType(Scrollable),
        )) {
          if (scrollable.widget.axisDirection == AxisDirection.down) {
            expect(
              scrollable.position.maxScrollExtent,
              0,
              reason: 'Main controls fit without vertical scrolling at normal text size',
            );
          }
        }
      }
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/home-${size.width.toInt()}.png'),
      );
    });
  }
  testWidgets('team home follows illustrated theme at 390px', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appProvider.overrideWith(() => TestController(fixture))],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme(),
          home: const AppShell(path: '/home', child: TeamHomeScreen()),
        ),
      ),
    );
    await tester.runAsync(() async {
      for (final asset in [
        'assets/logo-universal.png',
        'assets/team-hero.png',
      ]) {
        await precacheImage(
          AssetImage(asset),
          tester.element(find.byType(MaterialApp)),
        );
      }
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/team-home-390.png'),
    );
    await tester.scrollUntilVisible(find.text('Rahim'), 300);
    expect(find.text('Rahim'), findsOneWidget);
  });
  for (final size in [const Size(390, 844), const Size(960, 600)]) {
    testWidgets(
      'one-to-one controls fit without scrolling at ${size.width.toInt()}px',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appProvider.overrideWith(
                () => TestController(
                  fixture.copy(
                    recipientId: 'worker',
                    messages: [
                      {
                        'id': 'reply',
                        'groupId': 'g',
                        'mode': 'direct',
                        'state': 'READY',
                        'senderId': 'worker',
                        'sourceLanguage': 'ta',
                        'sourceText': 'Bring the material',
                        'translations': [
                          {'language': 'ta', 'text': 'Bring the material'},
                        ],
                        'recipients': [
                          {
                            'userId': 'engineer',
                            'language': 'ta',
                            'state': 'DELIVERED',
                          },
                        ],
                      },
                    ],
                  ),
                ),
              ),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: appTheme(),
              home: const AppShell(path: '/speak', child: HomeScreen()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Ready to talk to Rahim'), findsOneWidget);
        expect(find.byTooltip('Read replies aloud'), findsOneWidget);
        expect(find.text('Recent Messages'), findsNothing);
        expect(find.text('Type instead'), findsNothing);
        expect(find.text('I speak'), findsOneWidget);
        expect(find.text('They hear'), findsOneWidget);
        for (final scrollable in tester.stateList<ScrollableState>(
          find.byType(Scrollable),
        )) {
          if (scrollable.widget.axisDirection == AxisDirection.down) {
            expect(scrollable.position.maxScrollExtent, 0);
          }
        }
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/direct-${size.width.toInt()}.png'),
        );
      },
    );
  }
  testWidgets('welcome fits a small phone', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appProvider.overrideWith(
            () => TestController(
              const AppState(
                loading: false,
                capabilities: {'developmentAuth': true},
              ),
            ),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme(),
          home: const WelcomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/welcome-390.png'),
    );
  });
  testWidgets('home remains usable with large accessible text', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appProvider.overrideWith(() => TestController(fixture))],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.6)),
            child: child!,
          ),
          home: const AppShell(path: '/home', child: HomeScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
