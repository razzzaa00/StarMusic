enum MusicSource { ytmusic, youtube, soundcloud }

MusicSource? musicSourceFromName(String? name) {
  switch (name) {
    case 'ytmusic':
      return MusicSource.ytmusic;
    case 'youtube':
      return MusicSource.youtube;
    case 'soundcloud':
      return MusicSource.soundcloud;
  }
  return null;
}

class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.source,
    this.album = '',
    this.duration = Duration.zero,
    this.thumbnail = '',
    this.url = '',
  });

  /// YouTube video id or SoundCloud numeric track id (an Apple Music id for some imported album tracks).
  final String id;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final String thumbnail;
  final String url;
  final MusicSource source;

  bool get isSoundCloud => source == MusicSource.soundcloud;

  bool get hasVideoId => !isSoundCloud && RegExp(r'^[\w-]{11}$').hasMatch(id);

  String get key => '${isSoundCloud ? 'sc' : 'yt'}:$id';

  List<String> get artists => artist
      .split(RegExp(r',|&| x | feat\.? | ft\.? ', caseSensitive: false))
      .map((a) => a.trim())
      .where((a) => a.isNotEmpty)
      .toList();

  Track copyWith({String? album, String? thumbnail}) => Track(
        id: id,
        title: title,
        artist: artist,
        source: source,
        album: album ?? this.album,
        duration: duration,
        thumbnail: thumbnail ?? this.thumbnail,
        url: url,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'duration': duration.inSeconds,
        'thumbnail': thumbnail,
        'url': url,
        'source': source.name,
      };

  /// Reads tracks saved by this app and tracks exported by StarMusic for PC.
  static Track? fromJson(Map<String, dynamic> json) {
    final rawSource = (json['source'] ?? json['platform'])?.toString();
    final url = (json['url'] ?? '').toString();
    var source = musicSourceFromName(rawSource);
    source ??= url.contains('soundcloud.com') ? MusicSource.soundcloud : (url.contains('youtu') ? MusicSource.youtube : null);
    var id = (json['id'] ?? '').toString();
    if (source == null || rawSource == 'local') return null;
    if (source != MusicSource.soundcloud && !RegExp(r'^[\w-]{11}$').hasMatch(id)) {
      final m = RegExp(r'(?:v=|youtu\.be/)([\w-]{11})').firstMatch(url);
      // PC album tracks carry an Apple Music id: kept, and found on YouTube by name when played.
      if (m == null && '${json['title'] ?? ''}'.trim().isEmpty) return null;
      if (m != null) id = m.group(1)!;
    }
    final d = json['duration'];
    return Track(
      id: id,
      title: (json['title'] ?? '').toString(),
      artist: (json['artist'] ?? '').toString(),
      album: (json['album'] ?? '').toString(),
      duration: Duration(seconds: d is num ? d.round() : int.tryParse('$d') ?? 0),
      thumbnail: (json['thumbnail'] ?? json['cover'] ?? '').toString(),
      url: url,
      source: source,
    );
  }

  @override
  bool operator ==(Object other) => other is Track && other.key == key;

  @override
  int get hashCode => key.hashCode;
}
