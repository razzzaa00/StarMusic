import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/track.dart';
import 'net.dart';
import 'soundcloud.dart';

class ResolvedStream {
  ResolvedStream(this.uri, {this.substitute});
  final Uri uri;

  /// Set when YouTube refused the track and the same song is played from SoundCloud.
  final Track? substitute;
}

class StreamResolver {
  StreamResolver(this._soundcloud, this._yt);

  final SoundCloudApi _soundcloud;
  final YoutubeExplode _yt;
  final Map<String, (ResolvedStream, DateTime)> _cache = {};
  final Map<String, Future<ResolvedStream?>> _inflight = {};

  static const _iosClient = {
    'clientName': 'IOS',
    'clientVersion': '21.26.4',
    'deviceMake': 'Apple',
    'deviceModel': 'iPhone16,2',
    'userAgent': 'com.google.ios.youtube/21.26.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)',
    'osName': 'iPhone',
    'osVersion': '18.3.2.22D82',
    'hl': 'en',
    'gl': 'FR',
  };

  Future<ResolvedStream?> resolve(Track track) {
    final cached = _cache[track.key];
    if (cached != null && DateTime.now().difference(cached.$2) < const Duration(hours: 3)) {
      return Future.value(cached.$1);
    }
    return _inflight[track.key] ??= _resolve(track).then((r) {
      if (r != null) _cache[track.key] = (r, DateTime.now());
      return r;
    }).whenComplete(() {
      _inflight.remove(track.key);
    });
  }

  Future<ResolvedStream?> _resolve(Track track) async {
    if (track.isSoundCloud) {
      final uri = await _soundcloud.streamUrl(track).catchError((_) => null);
      return uri == null ? null : ResolvedStream(uri);
    }
    final videoId = track.hasVideoId ? track.id : await _findVideoId(track).catchError((_) => null);
    if (videoId != null) {
      final hls = await _youtubeHls(videoId).catchError((_) => null);
      if (hls != null) return ResolvedStream(hls);
      final direct = await _youtubeExplode(videoId).catchError((_) => null);
      if (direct != null) return ResolvedStream(direct);
    }
    return _soundCloudSubstitute(track);
  }

  Future<String?> _findVideoId(Track track) async {
    final results = await _yt.search.search('${track.artist} ${track.title}'.trim()).timeout(const Duration(seconds: 8));
    return results.isEmpty ? null : results.first.id.value;
  }

  Future<Uri?> _youtubeHls(String videoId) async {
    final json = await postJson(
      Uri.parse('https://www.youtube.com/youtubei/v1/player?prettyPrint=false'),
      {
        'context': {'client': _iosClient},
        'videoId': videoId,
        'contentCheckOk': true,
        'racyCheckOk': true,
      },
      headers: {
        'User-Agent': _iosClient['userAgent']!,
        'X-YouTube-Client-Name': '5',
        'X-YouTube-Client-Version': _iosClient['clientVersion']!,
      },
      timeout: const Duration(seconds: 8),
    );
    final streaming = json is Map ? json['streamingData'] : null;
    final url = streaming is Map ? streaming['hlsManifestUrl'] : null;
    return url is String ? Uri.parse(url) : null;
  }

  Future<Uri?> _youtubeExplode(String videoId) async {
    final manifest = await _yt.videos.streams.getManifest(videoId).timeout(const Duration(seconds: 8));
    if (manifest.audioOnly.isEmpty) return null;
    return manifest.audioOnly.withHighestBitrate().url;
  }

  Future<ResolvedStream?> _soundCloudSubstitute(Track track) async {
    final title = cleanTitle(track.title, track.artists);
    final artist = track.artists.isEmpty ? '' : track.artists.first;
    final candidates = await _soundcloud.search('$artist $title'.trim(), limit: 10).catchError((_) => <Track>[]);
    final wanted = normalize(title).split(' ').where((w) => w.length > 1).toSet();
    Track? best;
    var bestScore = 0.0;
    for (final c in candidates) {
      final have = normalize('${c.title} ${c.artist}');
      final hits = wanted.where(have.contains).length;
      var score = wanted.isEmpty ? 0.0 : hits / wanted.length;
      if (normalize(c.artist).contains(normalize(artist)) || normalize(c.title).contains(normalize(artist))) score += 0.5;
      if (track.duration > Duration.zero && (c.duration - track.duration).inSeconds.abs() > 20) score -= 0.4;
      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    if (best == null || bestScore < 0.9) return null;
    final uri = await _soundcloud.streamUrl(best).catchError((_) => null);
    return uri == null ? null : ResolvedStream(uri, substitute: best);
  }
}

String normalize(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[àáâãä]'), 'a')
    .replaceAll(RegExp(r'[èéêë]'), 'e')
    .replaceAll(RegExp(r'[ìíîï]'), 'i')
    .replaceAll(RegExp(r'[òóôõö]'), 'o')
    .replaceAll(RegExp(r'[ùúûü]'), 'u')
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim();

/// Strips video decorations ("(Official Video)", "[Lyrics]", "Artist - ") so the song can be found elsewhere.
String cleanTitle(String title, List<String> artists) {
  var t = title.replaceAll(RegExp(r'[\(\[][^\)\]]*(official|video|audio|lyrics?|visuali[sz]er|clip|hd|4k)[^\)\]]*[\)\]]', caseSensitive: false), '');
  final dash = t.indexOf(' - ');
  if (dash > 0) {
    final head = normalize(t.substring(0, dash));
    if (artists.any((a) => head.contains(normalize(a)))) t = t.substring(dash + 3);
  }
  return t.replaceAll(RegExp(r'\s+'), ' ').trim();
}
