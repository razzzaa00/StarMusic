import '../models/track.dart';
import 'soundcloud.dart';
import 'stream_resolver.dart' show normalize;
import 'youtube.dart';
import 'youtube_music.dart';

enum SearchScope { all, ytmusic, youtube, soundcloud }

class SearchService {
  SearchService(this.ytm, this.yt, this.sc);
  final YouTubeMusicApi ytm;
  final YouTubeApi yt;
  final SoundCloudApi sc;

  Future<List<Track>> searchOne(MusicSource source, String query) {
    switch (source) {
      case MusicSource.ytmusic:
        return ytm.search(query);
      case MusicSource.youtube:
        return yt.search(query);
      case MusicSource.soundcloud:
        return sc.search(query);
    }
  }

  /// Emits the merged list each time one platform answers.
  Stream<List<Track>> search(String query, SearchScope scope) async* {
    final sources = scope == SearchScope.all
        ? MusicSource.values
        : [MusicSource.values.firstWhere((s) => s.name == scope.name)];
    final buckets = <MusicSource, List<Track>>{};
    final pending = {for (final s in sources) s: searchOne(s, query).catchError((_) => <Track>[])};
    final remaining = pending.keys.toSet();
    while (remaining.isNotEmpty) {
      final done = await Future.any(remaining.map((s) => pending[s]!.then((r) => (s, r))));
      remaining.remove(done.$1);
      buckets[done.$1] = done.$2;
      yield merge(query, sources, buckets);
    }
  }

  static List<Track> merge(String query, List<MusicSource> order, Map<MusicSource, List<Track>> buckets) {
    final words = normalize(query).split(' ').where((w) => w.isNotEmpty).toList();
    final seen = <String, int>{};
    final entries = <(Track, int, int)>[];
    for (final source in order) {
      final list = buckets[source] ?? const [];
      for (var rank = 0; rank < list.length; rank++) {
        final t = list[rank];
        final idx = seen[t.key];
        if (idx != null) {
          if (entries[idx].$1.album.isEmpty && t.album.isNotEmpty) {
            entries[idx] = (entries[idx].$1.copyWith(album: t.album), entries[idx].$2, entries[idx].$3);
          }
          continue;
        }
        seen[t.key] = entries.length;
        entries.add((t, rank, _score(t, words)));
      }
    }
    final indexed = entries.asMap().entries.toList()
      ..sort((a, b) {
        final byScore = b.value.$3.compareTo(a.value.$3);
        if (byScore != 0) return byScore;
        final byRank = a.value.$2.compareTo(b.value.$2);
        return byRank != 0 ? byRank : a.key.compareTo(b.key);
      });
    return indexed.map((e) => e.value.$1).toList();
  }

  static int _score(Track t, List<String> words) {
    final main = normalize('${t.title} ${t.artist}');
    final album = normalize(t.album);
    var score = 0;
    for (final w in words) {
      if (main.contains(w)) {
        score += 2;
      } else if (album.contains(w)) {
        score += 1;
      }
    }
    return score;
  }
}
