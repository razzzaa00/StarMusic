import 'dart:convert';

import '../models/track.dart';
import 'net.dart';
import 'soundcloud.dart';

class ImportedPlaylist {
  const ImportedPlaylist(this.name, this.tracks);
  final String name;
  final List<Track> tracks;
}

/// Turns a public Spotify, YouTube, YouTube Music or SoundCloud playlist link into StarMusic tracks.
class PlaylistImporter {
  PlaylistImporter(this._soundcloud);

  final SoundCloudApi _soundcloud;

  static final _spotify = RegExp(r'(?:open\.spotify\.com/(?:intl-\w+/)?(?:embed/)?|spotify:)(playlist|album)[/:]([A-Za-z0-9]{22})');
  static final _youtubeList = RegExp(r'[?&]list=([\w-]+)');
  static final _soundcloudSet = RegExp(r'soundcloud\.com/[^/\s]+/sets/[^\s?#]+');

  Future<ImportedPlaylist> load(String link) async {
    final text = link.trim();
    final sp = _spotify.firstMatch(text);
    if (sp != null) return _spotifyList(sp.group(1)!, sp.group(2)!);
    final sc = _soundcloudSet.firstMatch(text);
    if (sc != null) {
      final (name, tracks) = await _soundcloud.playlist('https://${sc.group(0)}');
      return ImportedPlaylist(name, tracks);
    }
    final yt = _youtubeList.firstMatch(text);
    if (yt != null) return _youtubePlaylist(yt.group(1)!, text.contains('music.youtube.com'));
    throw const FormatException('unsupported link');
  }

  /// Spotify's embed page lists the tracks without an account (up to about 100).
  /// Tracks keep their Spotify id and are found on YouTube by name when played.
  Future<ImportedPlaylist> _spotifyList(String kind, String id) async {
    final res = await httpClient.get(Uri.parse('https://open.spotify.com/embed/$kind/$id'), headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36',
      'Accept-Language': 'en-US,en;q=0.9',
    }).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) throw HttpStatusException(res.statusCode, res.request!.url);
    final m = RegExp(r'<script id="__NEXT_DATA__"[^>]*>([\s\S]*?)</script>').firstMatch(utf8.decode(res.bodyBytes));
    if (m == null) throw const FormatException('private or unknown Spotify playlist');
    final entity = (jsonDecode(m.group(1)!) as Map)['props']?['pageProps']?['state']?['data']?['entity'];
    if (entity is! Map) throw const FormatException('private or unknown Spotify playlist');
    final cover = entity['coverArt']?['sources'] is List && (entity['coverArt']['sources'] as List).isNotEmpty
        ? '${entity['coverArt']['sources'][0]['url']}'
        : '';
    final list = entity['trackList'] is List ? entity['trackList'] as List : const [];
    final tracks = list.whereType<Map>().where((t) => '${t['title'] ?? ''}'.trim().isNotEmpty).map((t) {
      final uri = '${t['uri'] ?? ''}';
      return Track(
        id: uri.split(':').last,
        title: '${t['title']}'.trim(),
        artist: '${t['subtitle'] ?? ''}'.replaceAll(' ', ' ').trim(),
        album: kind == 'album' ? '${entity['name'] ?? ''}' : '',
        duration: Duration(milliseconds: ((t['duration'] ?? 0) as num).round()),
        thumbnail: kind == 'album' ? cover : '',
        url: uri.startsWith('spotify:track:') ? 'https://open.spotify.com/track/${uri.split(':').last}' : '',
        source: MusicSource.youtube,
      );
    }).toList();
    return ImportedPlaylist('${entity['name'] ?? 'Spotify'}', tracks);
  }

  /// Reads the playlist page from YouTube's web API; it now lists videos as "lockup" items.
  Future<ImportedPlaylist> _youtubePlaylist(String id, bool music) async {
    const client = {'clientName': 'WEB', 'clientVersion': '2.20251020.01.00', 'hl': 'en', 'gl': 'FR'};
    final endpoint = Uri.parse('https://www.youtube.com/youtubei/v1/browse?prettyPrint=false');
    var page = await postJson(endpoint, {'context': {'client': client}, 'browseId': 'VL$id'}, timeout: const Duration(seconds: 15));
    final title = page is Map ? '${page['metadata']?['playlistMetadataRenderer']?['title'] ?? 'YouTube'}' : 'YouTube';
    final tracks = <Track>[];
    final seen = <String>{};
    for (var guard = 0; guard < 10 && page != null; guard++) {
      String? next;
      void walk(dynamic node) {
        if (node is Map) {
          final lockup = node['lockupViewModel'];
          if (lockup is Map && lockup['contentType'] == 'LOCKUP_CONTENT_TYPE_VIDEO') {
            final t = _lockupTrack(lockup, music);
            if (t != null && seen.add(t.id)) tracks.add(t);
          }
          final token = node['continuationCommand']?['token'];
          if (token is String) next = token;
          node.values.forEach(walk);
        } else if (node is List) {
          node.forEach(walk);
        }
      }
      walk(page);
      if (next == null || tracks.length >= 1000) break;
      page = await postJson(endpoint, {'context': {'client': client}, 'continuation': next}, timeout: const Duration(seconds: 15));
    }
    if (tracks.isEmpty && page is Map && page['alerts'] != null) throw const FormatException('private or unknown YouTube playlist');
    return ImportedPlaylist(title, tracks);
  }

  static Track? _lockupTrack(Map lockup, bool music) {
    final id = '${lockup['contentId'] ?? ''}';
    final meta = lockup['metadata']?['lockupMetadataViewModel'];
    final title = '${meta?['title']?['content'] ?? ''}'.trim();
    if (!RegExp(r'^[\w-]{11}$').hasMatch(id) || title.isEmpty) return null;
    final rows = meta?['metadata']?['contentMetadataViewModel']?['metadataRows'];
    final author = rows is List && rows.isNotEmpty ? '${rows.first['metadataParts']?[0]?['text']?['content'] ?? ''}' : '';
    final badge = RegExp(r'"text":\s*"(\d+(?::\d{2}){1,2})"').firstMatch(jsonEncode(lockup['contentImage'] ?? const {}));
    var duration = Duration.zero;
    if (badge != null) {
      final parts = badge.group(1)!.split(':').map(int.parse).toList();
      duration = Duration(seconds: parts.fold(0, (acc, p) => acc * 60 + p));
    }
    return Track(
      id: id,
      title: title,
      artist: author.replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), ''),
      duration: duration,
      thumbnail: 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
      url: 'https://www.youtube.com/watch?v=$id',
      source: music ? MusicSource.ytmusic : MusicSource.youtube,
    );
  }
}
