import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/track.dart';
import '../services/stream_resolver.dart';
import 'equalizer.dart';
import 'library.dart';

enum RepeatSetting { off, all, one }

class PlayerController extends ChangeNotifier {
  PlayerController(this._resolver, this._library, {this.equalizer})
      : _player = AudioPlayer(
          audioPipeline: equalizer?.effect == null ? null : AudioPipeline(androidAudioEffects: [equalizer!.effect!]),
        ) {
    _player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) _onCompleted();
      notifyListeners();
    });
  }

  final StreamResolver _resolver;
  final Library _library;
  final EqualizerController? equalizer;
  final AudioPlayer _player;
  AudioPlayer get audio => _player;

  List<Track> _original = [];
  List<Track> queue = [];
  int index = -1;
  bool shuffle = false;
  RepeatSetting repeat = RepeatSetting.off;
  bool loading = false;
  String? error;

  /// The SoundCloud track actually playing when YouTube refused the current one.
  Track? substitute;
  int _loadToken = 0;

  Track? get current => index >= 0 && index < queue.length ? queue[index] : null;
  bool get playing => _player.playing;
  final StreamController<Track?> _currentChanges = StreamController.broadcast();
  Stream<Track?> get currentStream => _currentChanges.stream;

  Future<void> playQueue(List<Track> tracks, int start) async {
    if (tracks.isEmpty) return;
    _original = List.of(tracks);
    final first = tracks[start.clamp(0, tracks.length - 1)];
    if (shuffle) {
      final rest = List.of(tracks)..remove(first);
      rest.shuffle(Random());
      queue = [first, ...rest];
      index = 0;
    } else {
      queue = List.of(tracks);
      index = start.clamp(0, tracks.length - 1);
    }
    await _load();
  }

  Future<void> playNext(Track t) async {
    if (current == null) return playQueue([t], 0);
    queue.insert(index + 1, t);
    _original.add(t);
    notifyListeners();
  }

  void addToQueue(Track t) {
    if (current == null) {
      playQueue([t], 0);
      return;
    }
    queue.add(t);
    _original.add(t);
    notifyListeners();
  }

  Future<void> jumpTo(int i) async {
    if (i < 0 || i >= queue.length) return;
    index = i;
    await _load();
  }

  Future<void> _load() async {
    final track = current;
    if (track == null) return;
    final token = ++_loadToken;
    loading = true;
    error = null;
    substitute = null;
    _currentChanges.add(track);
    notifyListeners();
    await _player.stop();
    final resolved = await _resolver.resolve(track);
    if (token != _loadToken) return;
    if (resolved == null) {
      loading = false;
      error = 'Impossible de lire ce morceau';
      notifyListeners();
      if (index < queue.length - 1) {
        await Future.delayed(const Duration(milliseconds: 800));
        if (token == _loadToken) await next();
      }
      return;
    }
    substitute = resolved.substitute;
    try {
      await _player.setAudioSource(AudioSource.uri(resolved.uri));
      if (token != _loadToken) return;
      loading = false;
      notifyListeners();
      _library.addToHistory(track);
      unawaited(_player.play());
      unawaited(equalizer?.attach().catchError((_) {}));
      _prefetchNext();
    } catch (_) {
      if (token != _loadToken) return;
      loading = false;
      error = 'Impossible de lire ce morceau';
      notifyListeners();
    }
  }

  void _prefetchNext() {
    if (index + 1 < queue.length) unawaited(_resolver.resolve(queue[index + 1]));
  }

  void _onCompleted() {
    if (repeat == RepeatSetting.one) {
      _player.seek(Duration.zero);
      _player.play();
    } else {
      next(auto: true);
    }
  }

  Future<void> next({bool auto = false}) async {
    if (queue.isEmpty) return;
    if (index + 1 < queue.length) {
      index++;
    } else if (repeat == RepeatSetting.all || !auto) {
      index = 0;
    } else {
      await _player.pause();
      await _player.seek(Duration.zero);
      return;
    }
    await _load();
  }

  Future<void> previous() async {
    if (_player.position > const Duration(seconds: 3) || index <= 0) {
      await _player.seek(Duration.zero);
      return;
    }
    index--;
    await _load();
  }

  Future<void> togglePlay() async {
    if (current == null) return;
    if (_player.playing) {
      await _player.pause();
    } else if (_player.processingState == ProcessingState.idle) {
      await _load();
    } else {
      await _player.play();
    }
  }

  Future<void> seek(Duration d) => _player.seek(d);

  void toggleShuffle() {
    shuffle = !shuffle;
    final cur = current;
    if (cur != null) {
      if (shuffle) {
        final rest = List.of(queue)..remove(cur);
        rest.shuffle(Random());
        queue = [cur, ...rest];
        index = 0;
      } else {
        queue = List.of(_original);
        index = max(0, queue.indexOf(cur));
      }
    }
    notifyListeners();
  }

  void cycleRepeat() {
    repeat = RepeatSetting.values[(repeat.index + 1) % RepeatSetting.values.length];
    notifyListeners();
  }

  void removeFromQueue(int i) {
    if (i == index || i < 0 || i >= queue.length) return;
    final t = queue.removeAt(i);
    _original.remove(t);
    if (i < index) index--;
    notifyListeners();
  }
}

/// Bridges the player to the lock screen, Control Center and headphone buttons.
class StarAudioHandler extends BaseAudioHandler with SeekHandler {
  StarAudioHandler(this._controller) {
    final audio = _controller.audio;
    audio.playbackEventStream.listen((_) => _broadcast());
    audio.playingStream.listen((_) => _broadcast());
    _controller.currentStream.listen((t) {
      if (t == null) return;
      mediaItem.add(MediaItem(
        id: t.key,
        title: t.title,
        artist: t.artist,
        album: t.album.isEmpty ? null : t.album,
        duration: t.duration > Duration.zero ? t.duration : null,
        artUri: t.thumbnail.isEmpty ? null : Uri.tryParse(t.thumbnail),
      ));
    });
    audio.durationStream.listen((d) {
      final item = mediaItem.value;
      if (item != null && d != null) mediaItem.add(item.copyWith(duration: d));
    });
  }

  final PlayerController _controller;

  void _broadcast() {
    final audio = _controller.audio;
    playbackState.add(PlaybackState(
      controls: [MediaControl.skipToPrevious, audio.playing ? MediaControl.pause : MediaControl.play, MediaControl.skipToNext],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[audio.processingState]!,
      playing: audio.playing,
      updatePosition: audio.position,
      bufferedPosition: audio.bufferedPosition,
      speed: audio.speed,
    ));
  }

  @override
  Future<void> play() async {
    if (!_controller.playing) await _controller.togglePlay();
  }

  @override
  Future<void> pause() => _controller.audio.pause();

  @override
  Future<void> seek(Duration position) => _controller.seek(position);

  @override
  Future<void> skipToNext() => _controller.next();

  @override
  Future<void> skipToPrevious() => _controller.previous();

  @override
  Future<void> stop() => _controller.audio.stop();
}
