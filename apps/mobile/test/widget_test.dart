import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mine2yourlingo/core/app_controller.dart';
import 'package:mine2yourlingo/core/design.dart';
import 'package:mine2yourlingo/features/auth/welcome_screen.dart';
import 'package:mine2yourlingo/features/communication/home_screen.dart';
import 'package:mine2yourlingo/features/settings/settings_screen.dart';

class TestController extends AppController {
  final AppState initial;
  TestController(this.initial);
  @override
  AppState build() => initial;
  AppState get snapshot => state;
}

Widget harness(Widget widget, AppState state) => ProviderScope(
  overrides: [appProvider.overrideWith(() => TestController(state))],
  child: MaterialApp(
    theme: appTheme(),
    home: Scaffold(body: widget),
  ),
);
void main() {
  testWidgets('login-free start has no phone, OTP or confirmation form', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(const WelcomeScreen(), const AppState(loading: false)),
    );
    expect(find.text('Connect & continue'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Login with your phone'), findsNothing);
  });
  testWidgets('voice capture cannot start without a group', (tester) async {
    await tester.pumpWidget(
      harness(
        const HomeScreen(),
        const AppState(
          loading: false,
          user: {
            'id': 'u',
            'displayName': 'Priya',
            'spokenLanguage': 'ta',
            'listeningLanguage': 'ta',
          },
        ),
      ),
    );
    await tester.ensureVisible(find.byIcon(Icons.mic_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.mic_rounded));
    await tester.pump();
    expect(
      find.text('Create or join a group to start a conversation.'),
      findsOneWidget,
    );
    expect(find.text('Listening…'), findsNothing);
  });
  testWidgets(
    'settings keeps provider consent off and describes background limits',
    (tester) async {
      await tester.pumpWidget(
        harness(
          const SettingsScreen(),
          const AppState(
            loading: false,
            user: {
              'id': 'u',
              'displayName': 'Priya',
              'spokenLanguage': 'ta',
              'listeningLanguage': 'bn',
              'providerConsent': false,
            },
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Allow configured AI providers to process messages'),
        450,
      );
      final providerSwitch = find.widgetWithText(
        SwitchListTile,
        'Allow configured AI providers to process messages',
      );
      expect(tester.widget<SwitchListTile>(providerSwitch).value, false);
      expect(find.textContaining('end-to-end encryption'), findsOneWidget);
    },
  );
}
