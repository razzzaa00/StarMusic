import '../models/track.dart';
import 'net.dart';
import 'stream_resolver.dart' show cleanTitle;

class LyricLine {
  const LyricLine(this.time, this.text);
  final Duration time;
  final String text;
}

class Lyrics {
  const Lyrics({this.synced = const [], this.plain = ''});
  final List<LyricLine> synced;
  final String plain;
  bool get isEmpty => synced.isEmpty && plain.trim().isEmpty;
}

class LyricsService {
  final Map<String, Lyrics> _cache = {};

  Future<Lyrics> fetch(Track track) async {
    final hit = _cache[track.key];
    if (hit != null) return hit;
    final artist = track.artists.isEmpty ? track.artist : track.artists.first;
    final title = cleanTitle(track.title, track.artists);
    var lyrics = const Lyrics();
    try {
      final json = await getJson(Uri.https('lrclib.net', '/api/search', {'artist_name': artist, 'track_name': title}));
      if (json is List && json.isNotEmpty) {
        final list = json.cast<Map>();
        final secs = track.duration.inSeconds;
        list.sort((a, b) {
          final da = ((a['duration'] ?? 0) as num) - secs;
          final db = ((b['duration'] ?? 0) as num) - secs;
          final syncedA = a['syncedLyrics'] != null ? 0 : 1;
          final syncedB = b['syncedLyrics'] != null ? 0 : 1;
          return syncedA != syncedB ? syncedA - syncedB : da.abs().compareTo(db.abs());
        });
        final best = list.first;
        lyrics = Lyrics(synced: parseLrc('${best['syncedLyrics'] ?? ''}'), plain: '${best['plainLyrics'] ?? ''}');
      }
    } catch (_) {}
    return _cache[track.key] = lyrics;
  }
}

List<LyricLine> parseLrc(String lrc) {
  final out = <LyricLine>[];
  final tag = RegExp(r'\[(\d+):(\d+)(?:[.:](\d+))?\]');
  for (final raw in lrc.split('\n')) {
    final tags = tag.allMatches(raw).toList();
    if (tags.isEmpty) continue;
    final text = raw.substring(tags.last.end).trim();
    for (final m in tags) {
      final frac = m.group(3) ?? '0';
      final ms = int.parse(frac.padRight(3, '0').substring(0, 3));
      out.add(LyricLine(Duration(minutes: int.parse(m.group(1)!), seconds: int.parse(m.group(2)!), milliseconds: ms), text));
    }
  }
  out.sort((a, b) => a.time.compareTo(b.time));
  return out;
}
