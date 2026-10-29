@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starmusic/main.dart';
import 'package:starmusic/models/track.dart';
import 'package:starmusic/services/albums.dart';
import 'package:starmusic/services/lyrics.dart';
import 'package:starmusic/services/playlist_import.dart';
import 'package:starmusic/services/search.dart';
import 'package:starmusic/services/soundcloud.dart';
import 'package:starmusic/services/stream_resolver.dart';
import 'package:starmusic/services/updates.dart';
import 'package:starmusic/services/youtube.dart';
import 'package:starmusic/services/youtube_music.dart';
import 'package:starmusic/state/library.dart';
import 'package:starmusic/state/player.dart';
import 'package:starmusic/ui/app_scope.dart';
import 'package:starmusic/ui/screens/now_playing_screen.dart';

const demo = [
  Track(id: 'aaaaaaaaaaa', title: 'Miss The Rage', artist: 'Trippie Redd, Playboi Carti', album: 'Trip At Knight', duration: Duration(seconds: 211), source: MusicSource.ytmusic),
  Track(id: 'bbbbbbbbbbb', title: 'Trippie Redd – Miss The Rage ft. Playboi Carti (Official Visualizer)', artist: 'Trippie Redd', duration: Duration(seconds: 224), source: MusicSource.youtube),
  Track(id: '123456789', title: 'Miss The Rage (slowed + reverb)', artist: 'T.R.U.', duration: Duration(seconds: 257), source: MusicSource.soundcloud),
  Track(id: 'ccccccccccc', title: 'Wish', artist: 'Diplo, Trippie Redd', album: 'Wish - Single', duration: Duration(seconds: 179), source: MusicSource.ytmusic),
  Track(id: '987654321', title: 'Wish (Trippie Mix)', artist: 'Trippie Redd', album: "LIFE'S A TRIP", duration: Duration(seconds: 177), source: MusicSource.soundcloud),
];

class FakeSearch extends SearchService {
  FakeSearch(YouTubeApi yt, SoundCloudApi sc) : super(YouTubeMusicApi(), yt, sc);
  @override
  Stream<List<Track>> search(String query, SearchScope scope) => Stream.value(demo);
}

class FakeUpdates extends UpdateChecker {
  @override
  Future<String> installedVersion() async => '1.2.0';
  @override
  Future<AppUpdate?> check() async => null;
}

class FakeLyrics extends LyricsService {
  @override
  Future<Lyrics> fetch(Track track) async => Lyrics(synced: [
        for (var i = 0; i < 12; i++) LyricLine(Duration(seconds: i * 4), ['I been rockin\' since the day I came out', 'Miss the rage, I miss the rage', 'Yeah, yeah', 'Uh, uh'][i % 4]),
      ]);
}

Future<void> loadFonts() async {
  final base = '${Platform.environment['FLUTTER_ROOT'] ?? '/home/user/flutter'}/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final w in ['Regular', 'Medium', 'Bold']) {
    roboto.addFont(Future.value(ByteData.view(File('$base/Roboto-$w.ttf').readAsBytesSync().buffer)));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(File('$base/MaterialIcons-Regular.otf').readAsBytesSync().buffer)));
  await icons.load();
}

void main() {
  late AppServices services;

  setUp(() async {
    await loadFonts();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final yt = YouTubeApi();
    final sc = SoundCloudApi();
    final library = Library(prefs);
    library.toggleFavorite(demo[0]);
    library.toggleFavorite(demo[3]);
    library.importPcPlaylists('{"playlists":[{"name":"Chill","tracks":[{"title":"Wish","artist":"Diplo","source":"youtube","id":"ccccccccccc"}]},{"name":"Rap FR","tracks":[]}]}');
    final player = PlayerController(StreamResolver(sc, yt.client), library);
    services = AppServices(search: FakeSearch(yt, sc), albums: AlbumService(), lyrics: FakeLyrics(), library: library, player: player, importer: PlaylistImporter(sc), updates: FakeUpdates());
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(StarMusicApp(services: services));
    await tester.pump();
  }

  testWidgets('search', (tester) async {
    await pumpApp(tester);
    services.searchRequest.value = 'trippie redd';
    await tester.pump(const Duration(milliseconds: 100));
    services.player.queue = List.of(demo);
    services.player.index = 0;
    services.player.loading = false;
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    services.player.notifyListeners();
    await tester.pump(const Duration(milliseconds: 100));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/search.png'));
  });

  testWidgets('library', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Bibliothèque'));
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/library.png'));
  });

  testWidgets('settings', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Réglages'));
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/settings.png'));
  });

  testWidgets('now playing and lyrics', (tester) async {
    await pumpApp(tester);
    services.player.queue = List.of(demo);
    services.player.index = 0;
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    services.player.notifyListeners();
    await tester.pump();
    await tester.tap(find.text('Miss The Rage'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final err = tester.takeException();
    if (err != null) fail('build error: $err');
    expect(find.byType(NowPlayingScreen), findsOneWidget);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/now_playing.png'));
    await tester.tap(find.byIcon(Icons.lyrics_outlined));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/lyrics.png'));
  });
}
