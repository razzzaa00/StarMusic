@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:starmusic/models/track.dart';
import 'package:starmusic/services/albums.dart';
import 'package:starmusic/services/lyrics.dart';
import 'package:starmusic/services/search.dart';
import 'package:starmusic/services/soundcloud.dart';
import 'package:starmusic/services/stream_resolver.dart';
import 'package:starmusic/services/youtube.dart';
import 'package:starmusic/services/youtube_music.dart';

void main() {
  final yt = YouTubeApi();
  final sc = SoundCloudApi();
  final search = SearchService(YouTubeMusicApi(), yt, sc);
  final resolver = StreamResolver(sc, yt.client);

  test('all-platform search streams merged results', () async {
    final snapshots = await search.search('wish trippie redd', SearchScope.all).toList();
    final last = snapshots.last;
    // ignore: avoid_print
    print('snapshots: ${snapshots.map((s) => s.length).toList()}, sources: ${last.map((t) => t.source.name).toSet()}');
    expect(last, isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('soundcloud stream resolves', () async {
    final tracks = await sc.search('lofi hip hop');
    final r = await resolver.resolve(tracks.first);
    // ignore: avoid_print
    print('sc stream: ${r?.uri.host}');
    expect(r, isNotNull);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('youtube stream resolves or falls back to soundcloud', () async {
    const t = Track(id: 'fJ9rUzIMcZQ', title: 'Queen – Bohemian Rhapsody (Official Video Remastered)', artist: 'Queen Official', source: MusicSource.youtube, duration: Duration(seconds: 355));
    final r = await resolver.resolve(t);
    // ignore: avoid_print
    print('yt stream: ${r?.uri.host} substitute=${r?.substitute?.title} by ${r?.substitute?.artist}');
    expect(r, isNotNull);
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('lyrics and albums', () async {
    const t = Track(id: 'x', title: 'Miss The Rage', artist: 'Trippie Redd, Playboi Carti', source: MusicSource.ytmusic, duration: Duration(seconds: 211));
    final l = await LyricsService().fetch(t);
    final album = await AlbumService().find('Trip At Knight', 'Trippie Redd');
    final tracks = album == null ? [] : await AlbumService().tracks(album);
    // ignore: avoid_print
    print('lyrics synced=${l.synced.length} album=${album?.title} tracks=${tracks.length}');
    expect(album, isNotNull);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
