import 'dart:io';

import 'package:Tunein/blocs/music_player.dart';
import 'package:Tunein/blocs/themeService.dart';
import 'package:Tunein/store/locator.dart';
import 'package:flute_music_player/flute_music_player.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:Tunein/components/slider.dart';
import 'package:Tunein/globals.dart';
import 'package:Tunein/models/playerstate.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'controlls.dart';

class NowPlayingScreen extends StatefulWidget {
  @override
  NowPlayingScreenState createState() => NowPlayingScreenState();
}

class NowPlayingScreenState extends State<NowPlayingScreen> {
  final musicService = locator<MusicService>();
  final themeService = locator<ThemeService>();

  final _androidAppRetain = MethodChannel("android_app_retain");

  int maxVol;
  int currentVol;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final _screenHeight = MediaQuery.of(context).size.height;

    return StreamBuilder<MapEntry<PlayerState, Song>>(
      stream: musicService.playerState$,
      builder: (BuildContext context,
          AsyncSnapshot<MapEntry<PlayerState, Song>> snapshot) {
        if (!snapshot.hasData || snapshot.data.value.albumArt == null) {
          return Scaffold(
            backgroundColor: MyTheme.bgBottomBar,
          );
        }

        final Song _currentSong = snapshot.data.value;

        return Scaffold(
            body: StreamBuilder<List<int>>(
                stream: themeService.colors$,
                builder: (context, AsyncSnapshot<List<int>> snapshot) {
                  if (!snapshot.hasData) {
                    return Container();
                  }
                  final colors = snapshot.data;
                  return AnimatedContainer(
                    duration: Duration(milliseconds: 500),
                    curve: Curves.decelerate,
                    color: new Color(colors[0]),
                    child: getPlayinglayout(
                      _currentSong,
                      colors,
                      _screenHeight,
                    ),
                    // child: getAlternativeLayout(),
                  );
                }));
      },
    );
  }

  String getDuration(Song _song) {
    final double _temp = _song.duration / 1000;
    final int _minutes = (_temp / 60).floor();
    final int _seconds = (((_temp / 60) - _minutes) * 60).round();
    if (_seconds.toString().length != 1) {
      return _minutes.toString() + ":" + _seconds.toString();
    } else {
      return _minutes.toString() + ":0" + _seconds.toString();
    }
  }

  getPlayinglayout(_currentSong, List<int> colors, _screenHeight) {
    MapEntry<Song, Song> songs = musicService.getNextPrevSong(_currentSong);

    return Column(
      mainAxisSize: MainAxisSize.max,
      children: <Widget>[
        Container(
            constraints: BoxConstraints(
                maxHeight: _screenHeight / 2, minHeight: _screenHeight / 2),
            padding: const EdgeInsets.all(10),
            child: Dismissible(
              key: UniqueKey(),
              background: Image.file(File(songs.value.albumArt)),
              secondaryBackground: Image.file(File(songs.key.albumArt)),
              movementDuration: Duration(milliseconds: 500),
              resizeDuration: Duration(milliseconds: 2),
              onResize: () {
                print("resize");
              },
              dismissThresholds: const {
                DismissDirection.endToStart: 0.3,
                DismissDirection.startToEnd: 0.3
              },
              direction: DismissDirection.horizontal,
              onDismissed: (DismissDirection direction) {
                if (direction == DismissDirection.startToEnd) {
                  musicService.playPreviousSong();
                } else {
                  musicService.playNextSong();
                }
              },
              child: Image.file(File(_currentSong.albumArt)),
            )),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              boxShadow: [
                new BoxShadow(
                    color: Color(colors[0]),
                    blurRadius: 50,
                    spreadRadius: 50,
                    offset: new Offset(0, -20)),
              ],
            ),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        children: <Widget>[
                          Text(
                            _currentSong.title,
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Color(colors[1]).withOpacity(.7),
                              fontSize: 18,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              MyUtils.getArtists(_currentSong.artist),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Color(colors[1]).withOpacity(.7),
                                fontSize: 15,
                              ),
                            ),
                          )
                        ],
                      ),
                    )
                  ],
                ),
                NowPlayingSlider(colors),
                MusicBoardControls(colors),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
