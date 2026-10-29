import 'package:flutter/widgets.dart';

import '../services/albums.dart';
import '../services/lyrics.dart';
import '../services/playlist_import.dart';
import '../services/search.dart';
import '../services/updates.dart';
import '../state/library.dart';
import '../state/player.dart';

class AppServices {
  AppServices({required this.search, required this.albums, required this.lyrics, required this.library, required this.player, required this.importer, required this.updates});
  final SearchService search;
  final AlbumService albums;
  final LyricsService lyrics;
  final Library library;
  final PlayerController player;
  final PlaylistImporter importer;
  final UpdateChecker updates;

  /// Set to a query to switch to the Search tab and run it (artist taps, etc.).
  final ValueNotifier<String?> searchRequest = ValueNotifier(null);
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});
  final AppServices services;

  static AppServices of(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.services;

  @override
  bool updateShouldNotify(AppScope oldWidget) => false;
}
