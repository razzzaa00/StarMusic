import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/track.dart';

class YouTubeApi {
  final YoutubeExplode _yt = YoutubeExplode();

  Future<List<Track>> search(String query, {int limit = 15}) async {
    final results = await _yt.search.search(query);
    return results
        .where((v) => !v.isLive && (v.duration == null || (v.duration!.inSeconds >= 30 && v.duration!.inMinutes <= 20)))
        .take(limit)
        .map((v) => Track(
              id: v.id.value,
              title: v.title,
              artist: v.author.replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), ''),
              duration: v.duration ?? Duration.zero,
              thumbnail: 'https://i.ytimg.com/vi/${v.id.value}/hqdefault.jpg',
              url: 'https://www.youtube.com/watch?v=${v.id.value}',
              source: MusicSource.youtube,
            ))
        .toList();
  }

  YoutubeExplode get client => _yt;
}
