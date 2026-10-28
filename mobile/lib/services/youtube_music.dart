import '../models/track.dart';
import 'net.dart';

class YouTubeMusicApi {
  static const _songsParams = 'EgWKAQIIAWoMEA4QChADEAQQCRAF';
  static const _clientVersion = '1.20251020.01.00';

  Future<List<Track>> search(String query, {int limit = 15}) async {
    final json = await postJson(
      Uri.parse('https://music.youtube.com/youtubei/v1/search?prettyPrint=false'),
      {
        'context': {
          'client': {'clientName': 'WEB_REMIX', 'clientVersion': _clientVersion, 'hl': 'en', 'gl': 'FR'},
        },
        'query': query,
        'params': _songsParams,
      },
      headers: {'Origin': 'https://music.youtube.com'},
    );
    return parseSongs(json).take(limit).toList();
  }

  static List<Track> parseSongs(dynamic json) {
    final out = <Track>[];
    final tabs = _list(_at(json, ['contents', 'tabbedSearchResultsRenderer', 'tabs']));
    final sections = _list(_at(tabs.isEmpty ? null : tabs.first, ['tabRenderer', 'content', 'sectionListRenderer', 'contents']));
    for (final section in sections) {
      final items = [
        ..._list(_at(section, ['musicShelfRenderer', 'contents'])),
        ..._list(_at(section, ['itemSectionRenderer', 'contents'])),
        ..._list(_at(section, ['musicCardShelfRenderer', 'contents'])),
      ];
      for (final wrap in items) {
        final r = _at(wrap, ['musicResponsiveListItemRenderer']);
        if (r == null) continue;
        final videoId = (_at(r, ['playlistItemData', 'videoId']) ??
                _at(r, ['overlay', 'musicItemThumbnailOverlayRenderer', 'content', 'musicPlayButtonRenderer', 'playNavigationEndpoint', 'watchEndpoint', 'videoId']))
            ?.toString();
        if (videoId == null || !RegExp(r'^[\w-]{11}$').hasMatch(videoId)) continue;
        final cols = _list(r['flexColumns']);
        List runsOf(int i) => i < cols.length ? _list(_at(cols[i], ['musicResponsiveListItemFlexColumnRenderer', 'text', 'runs'])) : const [];
        final title = runsOf(0).map((x) => x['text']).join().trim();
        final segments = <String>[];
        var cur = StringBuffer();
        for (final run in runsOf(1)) {
          if (run['text'] == ' • ') {
            segments.add(cur.toString().trim());
            cur = StringBuffer();
          } else {
            cur.write(run['text']);
          }
        }
        segments.add(cur.toString().trim());
        final clean = segments.where((s) => s.isNotEmpty && !RegExp(r'^(song|video)$', caseSensitive: false).hasMatch(s)).toList();
        var duration = Duration.zero;
        if (clean.isNotEmpty) {
          final d = parseClock(clean.last);
          if (d != null) {
            duration = d;
            clean.removeLast();
          }
        }
        final artist = (clean.isNotEmpty ? clean[0] : '').replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '').trim();
        final album = clean.length > 1 ? clean[1] : '';
        final thumbs = _list(_at(r, ['thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']));
        var thumb = thumbs.isNotEmpty ? thumbs.last['url'].toString() : 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
        thumb = thumb.replaceAll(RegExp(r'=w\d+-h\d+[^&]*$'), '=w544-h544');
        if (title.isEmpty || (duration > Duration.zero && duration.inSeconds < 30)) continue;
        out.add(Track(
          id: videoId,
          title: title,
          artist: artist.isEmpty ? 'Unknown artist' : artist,
          album: album,
          duration: duration,
          thumbnail: thumb,
          url: 'https://music.youtube.com/watch?v=$videoId',
          source: MusicSource.ytmusic,
        ));
      }
    }
    return out;
  }
}

Duration? parseClock(String s) {
  final parts = s.trim().split(':');
  if (parts.length < 2 || parts.length > 3) return null;
  final nums = parts.map(int.tryParse).toList();
  if (nums.any((n) => n == null)) return null;
  var secs = 0;
  for (final n in nums) {
    secs = secs * 60 + n!;
  }
  return Duration(seconds: secs);
}

dynamic _at(dynamic node, List<String> path) {
  var cur = node;
  for (final key in path) {
    if (cur is Map && cur.containsKey(key)) {
      cur = cur[key];
    } else {
      return null;
    }
  }
  return cur;
}

List _list(dynamic v) => v is List ? v : const [];
