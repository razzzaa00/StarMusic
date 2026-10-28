import 'net.dart';
import 'stream_resolver.dart' show normalize;

class Album {
  const Album({required this.id, required this.title, required this.artist, this.year = '', this.artwork = ''});
  final String id;
  final String title;
  final String artist;
  final String year;
  final String artwork;
}

class AlbumTrack {
  const AlbumTrack({required this.number, required this.title, required this.artist, required this.duration});
  final int number;
  final String title;
  final String artist;
  final Duration duration;
}

class AlbumService {
  Future<List<Album>> search(String query) async {
    final json = await getJson(Uri.https('itunes.apple.com', '/search', {'term': query, 'entity': 'album', 'limit': '25', 'country': 'FR'}));
    final results = json is Map && json['results'] is List ? json['results'] as List : const [];
    return results.map((r) => Album(
          id: '${r['collectionId']}',
          title: '${r['collectionName'] ?? ''}',
          artist: '${r['artistName'] ?? ''}',
          year: '${r['releaseDate'] ?? ''}'.split('-').first,
          artwork: '${r['artworkUrl100'] ?? ''}'.replaceAll('100x100', '600x600'),
        )).toList();
  }

  /// Finds the album named on a track; requires the artist to match so namesakes are not opened.
  Future<Album?> find(String albumTitle, String artist) async {
    String n(String s) => normalize(s.replaceAll(RegExp(r'\s+-\s+(EP|Single)$', caseSensitive: false), '').replaceAll(RegExp(r'\((deluxe|expanded|remastered)[^)]*\)', caseSensitive: false), ''));
    final wanted = n(albumTitle);
    final who = normalize(artist);
    if (wanted.isEmpty) return null;
    final lists = await Future.wait([
      search('$artist $albumTitle').catchError((_) => <Album>[]),
      search(albumTitle).catchError((_) => <Album>[]),
    ]);
    final albums = lists.expand((l) => l).where((a) => who.isEmpty || normalize(a.artist).contains(who) || who.contains(normalize(a.artist))).toList();
    bool close(String t) => t.length >= 3 && wanted.length >= 3 && (t.startsWith(wanted) || wanted.startsWith(t));
    for (final a in albums) {
      if (n(a.title) == wanted) return a;
    }
    for (final a in albums) {
      if (close(n(a.title))) return a;
    }
    return null;
  }

  Future<List<AlbumTrack>> tracks(Album album) async {
    final json = await getJson(Uri.https('itunes.apple.com', '/lookup', {'id': album.id, 'entity': 'song', 'country': 'FR'}));
    final results = json is Map && json['results'] is List ? json['results'] as List : const [];
    final songs = results.where((r) => r['wrapperType'] == 'track').map((r) => AlbumTrack(
          number: (r['trackNumber'] ?? 0) as int,
          title: '${r['trackName'] ?? ''}',
          artist: '${r['artistName'] ?? album.artist}',
          duration: Duration(milliseconds: ((r['trackTimeMillis'] ?? 0) as num).round()),
        )).toList();
    songs.sort((a, b) => a.number.compareTo(b.number));
    return songs;
  }
}
