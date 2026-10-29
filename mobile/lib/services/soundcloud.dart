import '../models/track.dart';
import 'net.dart';

class SoundCloudApi {
  String _clientId = 'tHVbSbDP4TaoMbPppngv6Tdry83vNbMQ';

  Future<dynamic> _api(String path, Map<String, String> query) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final uri = Uri.https('api-v2.soundcloud.com', path, {...query, 'client_id': _clientId});
      try {
        return await getJson(uri);
      } on HttpStatusException catch (e) {
        if ((e.status == 401 || e.status == 403) && attempt == 0) {
          await _refreshClientId();
          continue;
        }
        rethrow;
      }
    }
  }

  Future<void> _refreshClientId() async {
    final page = await httpClient.get(Uri.parse('https://soundcloud.com'), headers: {'User-Agent': browserUserAgent});
    final scripts = RegExp(r'src="(https://a-v2\.sndcdn\.com/assets/[^"]+\.js)"').allMatches(page.body).map((m) => m.group(1)!).toList();
    for (final src in scripts.reversed.take(4)) {
      final code = await httpClient.get(Uri.parse(src));
      final m = RegExp(r'''client_id[:=]\s*["']([a-zA-Z0-9]{32})["']''').firstMatch(code.body);
      if (m != null) {
        _clientId = m.group(1)!;
        return;
      }
    }
  }

  Future<List<Track>> search(String query, {int limit = 15}) async {
    final json = await _api('/search/tracks', {'q': query, 'limit': '$limit'});
    final col = (json is Map && json['collection'] is List) ? json['collection'] as List : const [];
    return col.where(_playable).map(trackFromApi).toList();
  }

  static bool _playable(dynamic t) =>
      t is Map && t['kind'] == 'track' && t['streamable'] != false && t['policy'] != 'BLOCK' && t['policy'] != 'SNIP' && _hasClearStream(t);

  /// False when SoundCloud only offers encrypted (DRM) streams, which no player outside SoundCloud can read.
  static bool _hasClearStream(Map t) {
    final list = t['media'] is Map ? t['media']['transcodings'] : null;
    if (list is! List) return true;
    return list.any((x) => x is Map && (x['format']?['protocol'] == 'progressive' || x['format']?['protocol'] == 'hls'));
  }

  static Track trackFromApi(dynamic t) {
    final pm = (t['publisher_metadata'] as Map?) ?? const {};
    final user = (t['user'] as Map?) ?? const {};
    final art = (t['artwork_url'] ?? user['avatar_url'] ?? '').toString();
    final ms = (t['full_duration'] ?? t['duration'] ?? 0) as num;
    return Track(
      id: '${t['id']}',
      title: (t['title'] ?? 'Untitled').toString(),
      artist: (pm['artist'] ?? user['username'] ?? 'Unknown artist').toString(),
      album: (pm['album_title'] ?? '').toString(),
      duration: Duration(milliseconds: ms.round()),
      thumbnail: art.replaceAll('-large.', '-t500x500.'),
      url: (t['permalink_url'] ?? '').toString(),
      source: MusicSource.soundcloud,
    );
  }

  /// Loads a public SoundCloud set (playlist or album) from its link.
  Future<(String, List<Track>)> playlist(String url) async {
    final set = await _api('/resolve', {'url': url});
    if (set is! Map || set['kind'] != 'playlist') throw const FormatException('not a SoundCloud playlist');
    final items = (set['tracks'] is List ? set['tracks'] as List : const []).whereType<Map>().toList();
    // Sets list only the first tracks in full; the rest come as bare ids.
    final full = {for (final t in items.where((t) => t['title'] != null)) '${t['id']}': t};
    final missing = items.map((t) => '${t['id']}').where((id) => !full.containsKey(id)).toList();
    for (var i = 0; i < missing.length; i += 50) {
      final batch = await _api('/tracks', {'ids': missing.skip(i).take(50).join(',')});
      for (final t in (batch is List ? batch : const []).whereType<Map>()) {
        full['${t['id']}'] = t;
      }
    }
    final tracks = items.map((t) => full['${t['id']}']).where(_playable).map(trackFromApi).toList();
    return ('${set['title'] ?? 'SoundCloud'}', tracks);
  }

  /// Returns a progressive MP3 URL when SoundCloud offers one, otherwise an HLS playlist.
  Future<Uri?> streamUrl(Track track) async {
    final t = await _api('/tracks/${track.id}', const {});
    final list = (t is Map && t['media'] is Map && t['media']['transcodings'] is List) ? t['media']['transcodings'] as List : const [];
    Map? pick(String protocol) => list.cast<Map?>().firstWhere(
          (x) => x?['format']?['protocol'] == protocol && !RegExp('encrypted', caseSensitive: false).hasMatch('${x?['format']?['mime_type']}'),
          orElse: () => null,
        );
    final chosen = pick('progressive') ?? pick('hls');
    if (chosen == null) return null;
    final base = Uri.parse(chosen['url'] as String);
    final auth = t['track_authorization'];
    final res = await getJson(base.replace(queryParameters: {
      ...base.queryParameters,
      'client_id': _clientId,
      if (auth != null) 'track_authorization': '$auth',
    }));
    final url = res is Map ? res['url'] : null;
    return url == null ? null : Uri.parse('$url');
  }
}
