import 'package:flutter_test/flutter_test.dart';
import 'package:starmusic/models/track.dart';
import 'package:starmusic/services/lyrics.dart';
import 'package:starmusic/services/search.dart';
import 'package:starmusic/services/stream_resolver.dart';
import 'package:starmusic/services/updates.dart';
import 'package:starmusic/services/youtube_music.dart';

Track t(String id, String title, String artist, MusicSource s, {String album = ''}) =>
    Track(id: id, title: title, artist: artist, source: s, album: album);

void main() {
  test('merge ranks by query words in title or artist and keeps YouTube Music on duplicates', () {
    final merged = SearchService.merge('trippie redd miss the rage', MusicSource.values, {
      MusicSource.ytmusic: [t('aaaaaaaaaaa', 'Miss The Rage', 'Trippie Redd', MusicSource.ytmusic, album: 'Trip At Knight')],
      MusicSource.youtube: [
        t('bbbbbbbbbbb', 'Some other song', 'Nobody', MusicSource.youtube),
        t('aaaaaaaaaaa', 'Trippie Redd - Miss The Rage (Official Video)', 'Trippie Redd', MusicSource.youtube),
      ],
      MusicSource.soundcloud: [t('123456789', 'Miss The Rage', 'Trippie Redd', MusicSource.soundcloud)],
    });
    expect(merged.map((e) => e.key), ['yt:aaaaaaaaaaa', 'sc:123456789', 'yt:bbbbbbbbbbb']);
    expect(merged.first.source, MusicSource.ytmusic);
    expect(merged.first.album, 'Trip At Knight');
  });

  test('parseLrc reads timestamps and repeated tags', () {
    final lines = parseLrc('[00:12.50]Hello\n[01:02.003][00:05]Twice\nno tag');
    expect(lines.map((l) => l.text), ['Twice', 'Hello', 'Twice']);
    expect(lines[1].time, const Duration(seconds: 12, milliseconds: 500));
    expect(lines[2].time, const Duration(minutes: 1, seconds: 2, milliseconds: 3));
  });

  test('cleanTitle removes video decorations and the leading artist', () {
    expect(cleanTitle('Diplo - Wish (feat. Trippie Redd) (Official Music Video)', ['Diplo']), 'Wish (feat. Trippie Redd)');
    expect(cleanTitle('Queen – Bohemian Rhapsody [Lyrics]', ['Queen']), 'Queen – Bohemian Rhapsody');
  });

  test('Track.fromJson reads StarMusic PC exports and skips local files', () {
    final yt = Track.fromJson({'title': 'A', 'artist': 'B', 'source': 'youtube', 'id': 'dQw4w9WgXcQ', 'url': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ', 'duration': 213, 'cover': 'x.jpg'});
    expect(yt!.key, 'yt:dQw4w9WgXcQ');
    expect(yt.duration, const Duration(seconds: 213));
    expect(yt.thumbnail, 'x.jpg');
    final sc = Track.fromJson({'title': 'C', 'artist': 'D', 'source': 'soundcloud', 'id': '417474360', 'url': 'https://soundcloud.com/d/c'});
    expect(sc!.isSoundCloud, isTrue);
    expect(Track.fromJson({'title': 'E', 'source': 'local', 'id': 'song.mp3'}), isNull);
    expect(Track.fromJson({'title': 'F', 'source': 'youtube', 'id': 'bad', 'url': 'https://youtu.be/dQw4w9WgXcQ'})!.id, 'dQw4w9WgXcQ');
    final album = Track.fromJson({'title': 'East Hills', 'artist': 'Nbhd Nick', 'source': 'youtube', 'id': '1496112347'})!;
    expect(album.hasVideoId, isFalse);
    expect(sc.hasVideoId, isFalse);
    expect(yt.hasVideoId, isTrue);
    expect(Track.fromJson({'title': '', 'source': 'youtube', 'id': '1496112347'}), isNull);
  });

  test('YouTube Music song rows are parsed with artist, album and duration', () {
    Map run(String text) => {'text': text};
    final json = {
      'contents': {
        'tabbedSearchResultsRenderer': {
          'tabs': [
            {
              'tabRenderer': {
                'content': {
                  'sectionListRenderer': {
                    'contents': [
                      {
                        'musicShelfRenderer': {
                          'contents': [
                            {
                              'musicResponsiveListItemRenderer': {
                                'playlistItemData': {'videoId': 'dQw4w9WgXcQ'},
                                'flexColumns': [
                                  {'musicResponsiveListItemFlexColumnRenderer': {'text': {'runs': [run('Miss The Rage')]}}},
                                  {
                                    'musicResponsiveListItemFlexColumnRenderer': {
                                      'text': {'runs': [run('Song'), run(' • '), run('Trippie Redd'), run(' & '), run('Playboi Carti'), run(' • '), run('Trip At Knight'), run(' • '), run('3:31')]}
                                    }
                                  },
                                ],
                                'thumbnail': {'musicThumbnailRenderer': {'thumbnail': {'thumbnails': [{'url': 'https://lh3.googleusercontent.com/x=w60-h60-l90-rj'}]}}},
                              }
                            }
                          ]
                        }
                      }
                    ]
                  }
                }
              }
            }
          ]
        }
      }
    };
    final songs = YouTubeMusicApi.parseSongs(json);
    expect(songs, hasLength(1));
    expect(songs.first.artist, 'Trippie Redd & Playboi Carti');
    expect(songs.first.album, 'Trip At Knight');
    expect(songs.first.duration, const Duration(minutes: 3, seconds: 31));
    expect(songs.first.thumbnail, endsWith('=w544-h544'));
    expect(songs.first.artists, ['Trippie Redd', 'Playboi Carti']);
  });

  test('isNewer compares versions number by number', () {
    expect(isNewer('1.2.0', '1.1.9'), isTrue);
    expect(isNewer('1.10.0', '1.9.2'), isTrue);
    expect(isNewer('1.2.0', '1.2.0'), isFalse);
    expect(isNewer('1.1.2', '1.2.0'), isFalse);
    expect(isNewer('', '1.2.0'), isFalse);
  });
}
