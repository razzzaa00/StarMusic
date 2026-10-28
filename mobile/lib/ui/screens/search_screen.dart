import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../services/search.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/platform_icon.dart';
import '../widgets/track_tile.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  StreamSubscription<List<Track>>? _sub;
  List<Track> _results = [];
  bool _searching = false;
  String _lastQuery = '';
  late final AppServices _app;

  @override
  void initState() {
    super.initState();
    _app = AppScope.of(context);
    _app.searchRequest.addListener(_onRequest);
  }

  @override
  void dispose() {
    _app.searchRequest.removeListener(_onRequest);
    _sub?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onRequest() {
    final q = _app.searchRequest.value;
    if (q == null) return;
    _app.searchRequest.value = null;
    _controller.text = q;
    _run(q);
  }

  void _run(String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    _focus.unfocus();
    _sub?.cancel();
    setState(() {
      _lastQuery = q;
      _searching = true;
      _results = [];
    });
    _sub = _app.search.search(q, _app.library.searchScope).listen(
      (r) => setState(() => _results = r),
      onDone: () => setState(() => _searching = false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final library = _app.library;
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              textInputAction: TextInputAction.search,
              onSubmitted: _run,
              decoration: InputDecoration(
                hintText: 'Titres, artistes, albums…',
                prefixIcon: const Icon(Icons.search_rounded, color: StarColors.textDim),
                suffixIcon: ListenableBuilder(
                  listenable: _controller,
                  builder: (_, _) => _controller.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => _controller.clear()),
                ),
              ),
            ),
          ),
          ListenableBuilder(
            listenable: library,
            builder: (context, _) => SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final scope in SearchScope.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _ScopeChip(
                        scope: scope,
                        selected: library.searchScope == scope,
                        onTap: () {
                          library.setSearchScope(scope);
                          if (_lastQuery.isNotEmpty) _run(_lastQuery);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(height: 2, child: _searching ? const LinearProgressIndicator(minHeight: 2, backgroundColor: Colors.transparent) : null),
          Expanded(child: _lastQuery.isEmpty ? _recent(context) : _list(_results, empty: _searching ? '' : 'Aucun résultat')),
        ],
      ),
    );
  }

  Widget _recent(BuildContext context) => ListenableBuilder(
        listenable: _app.library,
        builder: (context, _) {
          final history = _app.library.history.take(30).toList();
          if (history.isEmpty) {
            return const Center(child: Text('Cherche un titre sur YouTube Music, YouTube et SoundCloud', textAlign: TextAlign.center, style: TextStyle(color: StarColors.textDim)));
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text('Écoutés récemment', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
            Expanded(child: _list(history, empty: '')),
          ]);
        },
      );

  Widget _list(List<Track> tracks, {required String empty}) {
    if (tracks.isEmpty) return Center(child: Text(empty, style: const TextStyle(color: StarColors.textDim)));
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: tracks.length,
      itemBuilder: (context, i) => TrackTile(track: tracks[i], onTap: () => _app.player.playQueue(tracks, i)),
    );
  }
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({required this.scope, required this.selected, required this.onTap});
  final SearchScope scope;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final source = scope == SearchScope.all ? null : MusicSource.values.firstWhere((s) => s.name == scope.name);
    return Material(
      color: selected ? StarColors.surfaceHigh : Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: selected ? StarColors.accent : StarColors.line)),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (source != null) ...[PlatformIcon(source), const SizedBox(width: 6)],
            Text(source == null ? 'Tout' : (source == MusicSource.ytmusic ? 'YT Music' : sourceNames[source]!), style: TextStyle(fontSize: 13, color: selected ? StarColors.text : StarColors.textDim)),
          ]),
        ),
      ),
    );
  }
}
