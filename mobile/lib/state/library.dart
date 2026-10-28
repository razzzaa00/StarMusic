import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';
import '../services/search.dart';

class Playlist {
  Playlist({required this.id, required this.name, List<Track>? tracks}) : tracks = tracks ?? [];
  final String id;
  String name;
  final List<Track> tracks;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'tracks': tracks.map((t) => t.toJson()).toList()};

  static Playlist fromJson(Map<String, dynamic> json) => Playlist(
        id: '${json['id']}',
        name: '${json['name'] ?? 'Playlist'}',
        tracks: _tracks(json['tracks']),
      );
}

List<Track> _tracks(dynamic list) =>
    (list is List ? list : const []).whereType<Map>().map((m) => Track.fromJson(Map<String, dynamic>.from(m))).whereType<Track>().toList();

class Library extends ChangeNotifier {
  Library(this._prefs) {
    favorites = _tracks(_read('favorites'));
    history = _tracks(_read('history'));
    final pls = _read('playlists');
    playlists = (pls is List ? pls : const []).whereType<Map>().map((m) => Playlist.fromJson(Map<String, dynamic>.from(m))).toList();
    searchScope = SearchScope.values.firstWhere((s) => s.name == _prefs.getString('searchScope'), orElse: () => SearchScope.all);
  }

  final SharedPreferences _prefs;
  late List<Track> favorites;
  late List<Track> history;
  late List<Playlist> playlists;
  late SearchScope searchScope;

  dynamic _read(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  void _save() {
    _prefs.setString('favorites', jsonEncode(favorites.map((t) => t.toJson()).toList()));
    _prefs.setString('history', jsonEncode(history.map((t) => t.toJson()).toList()));
    _prefs.setString('playlists', jsonEncode(playlists.map((p) => p.toJson()).toList()));
    _prefs.setString('searchScope', searchScope.name);
    notifyListeners();
  }

  bool isFavorite(Track t) => favorites.contains(t);

  void toggleFavorite(Track t) {
    if (!favorites.remove(t)) favorites.insert(0, t);
    _save();
  }

  void addToHistory(Track t) {
    history.remove(t);
    history.insert(0, t);
    if (history.length > 200) history.removeRange(200, history.length);
    _save();
  }

  void clearHistory() {
    history.clear();
    _save();
  }

  void setSearchScope(SearchScope scope) {
    searchScope = scope;
    _save();
  }

  Playlist createPlaylist(String name) {
    final p = Playlist(id: DateTime.now().microsecondsSinceEpoch.toString(), name: name.trim().isEmpty ? 'Nouvelle playlist' : name.trim());
    playlists.insert(0, p);
    _save();
    return p;
  }

  void renamePlaylist(Playlist p, String name) {
    if (name.trim().isEmpty) return;
    p.name = name.trim();
    _save();
  }

  void deletePlaylist(Playlist p) {
    playlists.remove(p);
    _save();
  }

  bool addToPlaylist(Playlist p, Track t) {
    if (p.tracks.contains(t)) return false;
    p.tracks.add(t);
    _save();
    return true;
  }

  void removeFromPlaylist(Playlist p, Track t) {
    p.tracks.remove(t);
    _save();
  }

  void reorderPlaylist(Playlist p, int from, int to) {
    final t = p.tracks.removeAt(from);
    p.tracks.insert(to, t);
    _save();
  }

  /// Imports the JSON written by "Export all playlists" in StarMusic for PC. Returns the number of tracks added.
  int importPcPlaylists(String content) {
    final json = jsonDecode(content);
    final list = json is Map ? json['playlists'] : json;
    var added = 0;
    for (final raw in (list is List ? list : const []).whereType<Map>()) {
      final name = '${raw['name'] ?? 'Playlist'}';
      final target = playlists.firstWhere((p) => p.name == name, orElse: () {
        final p = Playlist(id: '${DateTime.now().microsecondsSinceEpoch}${playlists.length}', name: name);
        playlists.add(p);
        return p;
      });
      for (final t in _tracks(raw['tracks'])) {
        if (!target.tracks.contains(t)) {
          target.tracks.add(t);
          added++;
        }
      }
    }
    _save();
    return added;
  }
}
