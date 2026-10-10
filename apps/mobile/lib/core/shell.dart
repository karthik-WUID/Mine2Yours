import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app_controller.dart';
import 'design.dart';
import 'languages.dart';
import 'team_theme.dart';

class AppShell extends ConsumerWidget {
  final String path;
  final Widget child;
  const AppShell({super.key, required this.path, required this.child});
  static const _paths = ['/home', '/history', '/phrases', '/team'];
  static const _icons = [
    Icons.home_rounded,
    Icons.history_rounded,
    Icons.chat_bubble_outline_rounded,
    Icons.people_alt_outlined,
  ];
  static const _labels = ['home', 'history', 'phrases', 'team'];
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final app = ref.read(appProvider.notifier);
    final selected = path.startsWith('/group') ? 3 : _paths.indexOf(path);
    final desktop = MediaQuery.sizeOf(context).width >= 980;
    final title =
        const {
          '/settings': 'Settings',
          '/languages': 'Languages',
          '/personnel': 'Member records',
          '/manage-teams': 'Manage teams',
          '/speak': 'Voice message',
        }.containsKey(path)
        ? const {
            '/settings': 'Settings',
            '/languages': 'Languages',
            '/personnel': 'Member records',
            '/manage-teams': 'Manage teams',
            '/speak': 'Voice message',
          }[path]!
        : path.startsWith('/group')
        ? 'Your group'
        : Labels.get(state.uiLanguage, _labels[selected < 0 ? 0 : selected]);
    final content = Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            desktop ? 34 : 20,
            desktop ? 24 : 8,
            desktop ? 34 : 16,
            10,
          ),
          child: Row(
            children: [
              if (!desktop)
                const Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Brand(width: 180),
                  ),
                )
              else
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              Tag(
                state.connected
                    ? 'Connected'
                    : state.error != null
                    ? 'Server offline'
                    : state.online
                    ? 'Connecting'
                    : 'Offline',
                color: state.connected ? teal : muted,
                icon: state.connected
                    ? Icons.wifi_rounded
                    : Icons.wifi_off_rounded,
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Settings',
                onPressed: () => context.go('/settings'),
                icon: const Icon(Icons.settings_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: navy,
                  elevation: 2,
                  shadowColor: blue.withValues(alpha: .2),
                ),
              ),
              if (desktop) ...[
                const SizedBox(width: 8),
                InitialAvatar(
                  memberDisplayName(state.user?['displayName']),
                  radius: 20,
                ),
              ],
            ],
          ),
        ),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Container(
              padding: const EdgeInsets.only(left: 14),
              decoration: BoxDecoration(
                color: const Color(0xfffff7e9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: Color(0xffad790d),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.error!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xff8f651a),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: app.reconnect,
                    child: const Text('Retry'),
                  ),
                  IconButton(
                    tooltip: 'Dismiss',
                    onPressed: app.clearError,
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
            ),
          ),
        Expanded(child: child),
      ],
    );
    return Scaffold(
      body: TeamBackdrop(
        child: SafeArea(
          child: desktop
              ? Row(
                  children: [
                    Container(
                      width: 228,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(right: BorderSide(color: border)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Brand(width: 185),
                            const SizedBox(height: 40),
                            const Padding(
                              padding: EdgeInsets.only(left: 12, bottom: 14),
                              child: Text(
                                'YOUR WORKSPACE',
                                style: TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 1.6,
                                  fontWeight: FontWeight.w700,
                                  color: muted,
                                ),
                              ),
                            ),
                            ...List.generate(
                              4,
                              (i) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _railItem(
                                  context,
                                  _icons[i],
                                  Labels.get(state.uiLanguage, _labels[i]),
                                  _paths[i],
                                  selected == i,
                                ),
                              ),
                            ),
                            const Spacer(),
                            const SizedBox(height: 16),
                            _railItem(
                              context,
                              Icons.settings_outlined,
                              'Settings',
                              '/settings',
                              path == '/settings',
                            ),
                            const Divider(height: 26),
                            Row(
                              children: [
                                InitialAvatar(
                                  memberDisplayName(state.user?['displayName']),
                                  radius: 19,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        memberDisplayName(
                                          state.user?['displayName'],
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        AppLanguage.of(state.language).name,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(child: content),
                  ],
                )
              : content,
        ),
      ),
      bottomNavigationBar: desktop
          ? null
          : ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              child: NavigationBar(
                selectedIndex: selected < 0 ? 0 : selected,
                height: 68,
                backgroundColor: Colors.white,
                indicatorColor: const Color(0xffe7f2ff),
                onDestinationSelected: (i) => context.go(_paths[i]),
                destinations: List.generate(
                  4,
                  (i) => NavigationDestination(
                    icon: Icon(_icons[i], color: muted),
                    selectedIcon: Icon(_icons[i], color: blue, size: 29),
                    label: Labels.get(state.uiLanguage, _labels[i]),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _railItem(
    BuildContext context,
    IconData icon,
    String label,
    String route,
    bool selected,
  ) => Material(
    color: selected ? const Color(0xffedf5ff) : Colors.transparent,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.go(route),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: selected ? blue : muted, size: 21),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? blue : muted,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
