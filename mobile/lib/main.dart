import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/albums.dart';
import 'services/lyrics.dart';
import 'services/search.dart';
import 'services/soundcloud.dart';
import 'services/stream_resolver.dart';
import 'services/youtube.dart';
import 'services/youtube_music.dart';
import 'state/equalizer.dart';
import 'state/library.dart';
import 'state/player.dart';
import 'ui/app_scope.dart';
import 'ui/screens/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final youtube = YouTubeApi();
  final soundcloud = SoundCloudApi();
  final library = Library(prefs);
  final equalizer = EqualizerController(prefs);
  final player = PlayerController(StreamResolver(soundcloud, youtube.client), library, equalizer: equalizer);

  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());
  await AudioService.init(
    builder: () => StarAudioHandler(player),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'io.github.razzzaa00.starmusic.playback',
      androidNotificationChannelName: 'Lecture',
      androidNotificationOngoing: true,
    ),
  );

  runApp(StarMusicApp(
    services: AppServices(
      search: SearchService(YouTubeMusicApi(), youtube, soundcloud),
      albums: AlbumService(),
      lyrics: LyricsService(),
      library: library,
      player: player,
    ),
  ));
}

class StarMusicApp extends StatelessWidget {
  const StarMusicApp({super.key, required this.services});
  final AppServices services;

  @override
  Widget build(BuildContext context) => AppScope(
        services: services,
        child: MaterialApp(
          title: 'StarMusic',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          home: const Shell(),
        ),
      );
}
