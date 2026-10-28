import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/platform_icon.dart';
import 'library_screen.dart';
import 'now_playing_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  late final AppServices _app;

  @override
  void initState() {
    super.initState();
    _app = AppScope.of(context);
    _app.searchRequest.addListener(_toSearch);
  }

  @override
  void dispose() {
    _app.searchRequest.removeListener(_toSearch);
    super.dispose();
  }

  void _toSearch() {
    if (_app.searchRequest.value != null && _tab != 0) setState(() => _tab = 0);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: _tab, children: const [SearchScreen(), LibraryScreen(), SettingsScreen()]),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MiniPlayer(),
            const Divider(),
            NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: const [
                NavigationDestination(icon: Icon(Icons.search_rounded), label: 'Recherche'),
                NavigationDestination(icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music_rounded), label: 'Bibliothèque'),
                NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: 'Réglages'),
              ],
            ),
          ],
        ),
      );
}

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = AppScope.of(context).player;
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final t = player.current;
        if (t == null) return const SizedBox.shrink();
        return Material(
          color: StarColors.surface,
          child: InkWell(
            onTap: () => Navigator.of(context).push(PageRouteBuilder(
              pageBuilder: (_, _, _) => const NowPlayingScreen(),
              transitionsBuilder: (_, anim, _, child) => SlideTransition(
                position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                child: child,
              ),
            )),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              StreamBuilder<Duration>(
                stream: player.audio.positionStream,
                builder: (_, snap) {
                  final total = player.audio.duration ?? t.duration;
                  final v = total.inMilliseconds <= 0 ? 0.0 : ((snap.data ?? Duration.zero).inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
                  return LinearProgressIndicator(value: v, minHeight: 2, backgroundColor: Colors.transparent);
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                child: Row(children: [
                  Artwork(t.thumbnail, size: 40),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
                      Row(children: [
                        PlatformIcon(player.substitute?.source ?? t.source, size: 11),
                        const SizedBox(width: 4),
                        Expanded(child: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: StarColors.textDim, fontSize: 12))),
                      ]),
                    ]),
                  ),
                  player.loading
                      ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                      : IconButton(icon: Icon(player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 30), onPressed: player.togglePlay),
                  IconButton(icon: const Icon(Icons.skip_next_rounded, size: 28), onPressed: player.next),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }
}
