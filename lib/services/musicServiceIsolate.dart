import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:Tunein/models/playerstate.dart';
import 'package:Tunein/plugins/nano.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';
import 'package:path/path.dart';
import 'package:flutter_isolate/flutter_isolate.dart';
import 'package:Tunein/plugins/upnp.dart' as UPnPPlugin;
import 'package:upnp/upnp.dart';

MethodChannel platform = MethodChannel('android_app_retain');

class musicServiceIsolate {
  static BehaviorSubject<MapEntry<PlayerState, Tune>> _playerState$ = BehaviorSubject<MapEntry<PlayerState, Tune>>.seeded(
    MapEntry(
      PlayerState.stopped,
      Tune(null, " ", " ", " ", null, null, null, [], null),
    ),
  );

  BehaviorSubject<MapEntry<PlayerState, Tune>> get playerState$ =>
      _playerState$;


  musicServiceIsolate(){
    WidgetsFlutterBinding.ensureInitialized();
    _initStreams();
  }

  void dispose() {
    newIsolate?.kill(priority: Isolate.immediate);
    newIsolate = null;
    newPluginEnabledIsolate?.kill();
    newPluginEnabledIsolate=null;
  }


  static Map<String, MapEntry<String,String>> filesToServe=Map();

// Temporary attributes

  static Map mapMetaData = Map();

// Isolate  methods and attributes

  SendPort newIsolateSendPort;
  SendPort newPluginEnabledIsolateSendPort;

  Isolate newIsolate;
  FlutterIsolate newPluginEnabledIsolate;

// default port to receive on

  ReceivePort defaultReceivePort = ReceivePort();


  Future<bool> callerCreateIsolate() async {

    ReceivePort receivePort = ReceivePort();


    newIsolate = await Isolate.spawn(
      callbackFunction,
      receivePort.sendPort,
    );


    newIsolateSendPort = await receivePort.first;
    return true;
  }

  Future<bool> callerCreatePluginEnabledIsolate() async {

    ReceivePort receivePort = ReceivePort();


    newPluginEnabledIsolate = await FlutterIsolate.spawn(
      pluginEnabledIsolateCallbackFunction,
      receivePort.sendPort,
    );


    newPluginEnabledIsolateSendPort = await receivePort.first;
    return true;
  }


  Future<dynamic> sendReceive(String messageToBeSent) async {

    ReceivePort port = ReceivePort();


    newIsolateSendPort.send(CrossIsolatesMessage<String>(
        sender: port.sendPort, message: messageToBeSent, command: null));


    return port.first;
  }

  //Sending any crossIsolateMessage

  Future<dynamic> sendCrossIsolateMessage(
      CrossIsolatesMessage messageToBeSent) async {

    ReceivePort port = ReceivePort();


    messageToBeSent = new CrossIsolatesMessage(
        sender: messageToBeSent.sender==null?port.sendPort:messageToBeSent.sender,
        message: messageToBeSent.message,
        command: messageToBeSent.command);

    newIsolateSendPort.send(messageToBeSent);

    return port.first;
  }

  ///This only takes strings as the plugin isolates only take primitive types
  Future<dynamic> sendCrossPluginIsolatesMessage(
      CrossIsolatesMessage messageToBeSent) async {

    ReceivePort port = ReceivePort();


    messageToBeSent = new CrossIsolatesMessage(
        sender: messageToBeSent.sender==null?port.sendPort:messageToBeSent.sender,
        message: messageToBeSent.message,
        command: messageToBeSent.command);

    newPluginEnabledIsolateSendPort.send([messageToBeSent.command,messageToBeSent.message,messageToBeSent.sender]);

    return port.first;
  }

  ///The callback function used in the regular isolate
  static void callbackFunction(SendPort callerSendPort) {

    ReceivePort newIsolateReceivePort = ReceivePort();


    callerSendPort.send(newIsolateReceivePort.sendPort);

    _sendNotFound(HttpResponse response) {
      response.write('Not found');
      response.statusCode = HttpStatus.notFound;
      response.close();
    }

    _handleGet(HttpRequest request) {
      // PENDING: Do more security checks here?
      final String fileID = request.uri.queryParameters["fileID"];
      try{
        String fileUri = fileID!=null?filesToServe[fileID.split(".")[0]].key:null;
        List<String> contentType = filesToServe[fileID.split(".")[0]].value.split("/");
        if(fileUri!=null){
          final File file = new File(fileUri);
          file.exists().then((bool found)  async{
            if (found) {
              request.response.headers.contentType = ContentType(contentType[0]??"audio",contentType[1]??"mpeg");
              //file.openRead().pipe(request.response).catchError((e) {print(e);});
              request.response.contentLength = file.statSync().size;
              await request.response.addStream(file.openRead());
            } else {
              _sendNotFound(request.response);
            }
          });
        }else{
          _sendNotFound(request.response);
        }
      }catch(e){
        print(e);
        _sendNotFound(request.response);
      }

    }

    HttpServer.bind('0.0.0.0', 8089, shared: true).then((HttpServer server) {
      server.listen((request) {
        print("got a request");
        switch (request.method) {
          case 'GET':
            _handleGet(request);
            break;

          default:
            request.response.statusCode = HttpStatus.METHOD_NOT_ALLOWED;
            request.response.close();
        }
      });
    });


    newIsolateReceivePort.listen((dynamic message) {
      CrossIsolatesMessage incomingMessage = message as CrossIsolatesMessage;

      switch(incomingMessage.command){
        case "registerAFileToBeServed":{
          //The message structure is like follow : MapEntry(id, MapEntry(uri, contentType))
          MapEntry<String,MapEntry<String,String>> newMessage = incomingMessage.message;
          filesToServe[newMessage.key]= MapEntry(newMessage.value.key,newMessage.value.value);
          incomingMessage.sender.send(true);
          break;
        }
        case "searchForCastDevices":{
          if(incomingMessage.message!=null){
            searchForCastingDevices((data){
              incomingMessage.sender.send(data);
            });
          }
          break;
        }
        case "readExternalDirectory":{
          if(incomingMessage.message!=null){
            readExtDir(incomingMessage.message,(dataPath){
              incomingMessage.sender.send(dataPath);
            });
          }
          break;
        }
        case "encodeSongsToStringList":{
          if(incomingMessage.message!=null){
            saveSongsToPref(incomingMessage.message,(data){
              incomingMessage.sender.send(data);
            });
          }
          break;
        }

        case "fetchAlbumsFromSongs":{
          if(incomingMessage.message!=null){
            fetchAlbumFromsongs(incomingMessage.message,(data){
              incomingMessage.sender.send(data);
            });
          }
          break;
        }

        //getAllTracksMetaData is not usable since platform channel methods are not available from an isolate yet
        case "getAllTracksMetadata":{
          if(incomingMessage.message!=null){
            fetchMetadataOfAllTracks(incomingMessage.message,(data){
              incomingMessage.sender.send(data);
            });
          }
          break;
        }

        case "encodeArtistsToStringList":{
          if(incomingMessage.message!=null){
            saveArtiststoPref(incomingMessage.message,(data){
              incomingMessage.sender.send(data);
            });
          }
          break;
        }
        default:
          break;
      }

      if (incomingMessage.sender != null) {
        incomingMessage.sender.send("OK");
      } else {}
    });
  }

  ///This callback function is used in the plugin enabled isolate
  static void pluginEnabledIsolateCallbackFunction(SendPort callerSendPort) {

    ReceivePort newIsolateReceivePort = ReceivePort();


    callerSendPort.send(newIsolateReceivePort.sendPort);


    newIsolateReceivePort.listen((dynamic message) {
      List<dynamic> incomingMessage = message as List<dynamic>;
      switch(incomingMessage[0] as String){
        case "test":{
          (incomingMessage[2] as SendPort).send(incomingMessage[1] as String);
          break;
        }
        case "getAllTracksMetadata":{
          if(incomingMessage[1]!=null){
            fetchMetadataOfAllTracks(incomingMessage[1],(data){
              (incomingMessage[2] as SendPort).send(data);
            });
          }
          break;
        }
      }
    });
  }

  //FetchingMetadata of all tracks methods

  static fetchMetadataOfAllTracks(List tracks, Function(List) callback) async{
    List _metaData=[];
    for (var track in tracks) {
      var data = await getFileMetaData(track);
      print(data);
      // updateLoadingTrack(track, _musicFiles.indexOf(track), _musicFiles.length);
      if (data!=null && data[2] != null) {
        if (data[2] is List<int>) {
          var digest = sha1.convert(data[2]).toString();
          writeImage(digest, data[2]);
          data[2] = digest;
          _metaData.add(data);
        } else {
          _metaData.add(data);
        }
      } else {
        _metaData.add(data);
      }
    }
    callback(_metaData);
  }

  static Future getFileMetaData(track) async {

    var value;
    try {
      if (mapMetaData[track] == null) {


        var metaValue = await platform
            .invokeMethod("getMetaData", <String, dynamic>{'filepath': track});
        return metaValue;
      } else {
        value = mapMetaData[track];
        return value;
      }
    } catch (e) {
      print(e);
    }

  }

  //flutter_isolate static callback
  static ReceivePort isolateTempPort = ReceivePort();
  static void callback(MapEntry<ReceivePort,String>data) async {

    isolateTempPort.listen((dataSenT) async{
      if(dataSenT!=null){
        MethodChannel platform = MethodChannel('android_app_retain');
        print(data.value);
        var metaValue = await platform
            .invokeMethod("getMetaData", <String, dynamic>{'filepath': data.value});
        data.key.sendPort.send(metaValue);

      }
    });

  }

  static Future<String> getLocalPath() async {
    Directory dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  static Future<File> getLocalFile() async {
    String path = await getLocalPath();
    return File('$path/filesmetadata.json');
  }

  static Future<File> writeImage(var hash, List<int> image) async {
    String path = await getLocalPath();
    File imagefile = File('$path/$hash');
    return imagefile.writeAsBytes(image);
  }

  //Fetching songs from directory
  static readExtDir(Directory dir, Function(String) callback) async {
    Stream<FileSystemEntity> sdContents = dir.list(recursive: true);
    sdContents = sdContents.handleError((data) {});
    await for (var data in sdContents) {
      if (data.path.endsWith(".mp3")) {
        if(validateMusicFile(data.path)){
          callback(data.path);
        };
      }
    }
    callback("0001");
  }

  static bool validateMusicFile(String path){
    String filename = basename(path);
    if(filename.startsWith(new RegExp(r'([_.\-\!\?])'))){
      return false;
    }
    return true;
  }

  // fetching albums from songs

  static fetchAlbumFromsongs(List<Tune> songs, Function(List<Album>) callback) async{
    Map<String, Album> albums = {};
    int currentIndex = 0;
    songs.forEach((Tune tune) {
      if (albums["${tune.album}${tune.artist}"] != null) {
        albums["${tune.album}${tune.artist}"].songs.add(tune);
      } else {
        albums["${tune.album}${tune.artist}"] =
        new Album(currentIndex, tune.album, tune.artist, tune.albumArt);
        albums["${tune.album}${tune.artist}"].songs.add(tune);
        currentIndex++;
      }
    });
    List<Album> newAlbumList = albums.values.toList();
    newAlbumList.forEach((album){
      album.songs.sort((a,b){
        if(a.numberInAlbum ==null || b.numberInAlbum==null) return 1;
        if(a.numberInAlbum < b.numberInAlbum) return -1;
        else return 1;
      });
    });
    newAlbumList.sort((a, b) {
      if (a.title == null || b.title == null) return 1;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    print("albums length : ${newAlbumList.length}");
    callback(newAlbumList);
  }

  //encoding artists to save in prefs in the main isolate

  static saveArtiststoPref(List<Artist> artists, Function(List<String>) callback) async{
    List<String> _encodedStrings = [];
    for (Artist artist in artists) {
      _encodedStrings.add(_encodeArtistToJson(artist));
    }
    print("encoded ${_encodedStrings.length} artist");
    callback(_encodedStrings);
  }

  static String _encodeArtistToJson(Artist artist) {
    final _ArtistMap = artist.toMap(artist);
    final data = json.encode(_ArtistMap);
    return data;
  }

  // encoding songs to save in prefs in main isolate

  static saveSongsToPref(List<Tune> songs, Function(List<String>) callback) async{
    List<String> _encodedStrings = [];
    for (Tune song in songs) {
      _encodedStrings.add(_encodeSongToJson(song));
    }
    print("encoded ${_encodedStrings.length} songs");
    callback(_encodedStrings);
  }

  static String _encodeSongToJson(Tune song) {
    final _songMap = song.toMap();
    final data = json.encode(_songMap);
    return data;
  }


  // Searching for casting devices


  static searchForCastingDevices(Function(List<Device>) callback) async{
    try{
      UPnPPlugin.upnp instance = UPnPPlugin.upnp();
      List<Device> devices = await instance.getDevices();
      print("found ${devices.length} devices");
      callback(devices);
    }catch(e){
      print(e);
      print(e.stack);
    }

  }

  void _initStreams() {
    _playerState$.listen((data){
      CrossIsolatesMessage messageToBeSent = new CrossIsolatesMessage<MapEntry<PlayerState,Tune>>(
          sender: null,
          message: data,
          command: "UPlayerstate");
      defaultReceivePort.sendPort.send(messageToBeSent);
    });
  }
}

//
// Helper class
//
class CrossIsolatesMessage<T> {
  final SendPort sender;
  final T message;
  final String command;

  CrossIsolatesMessage({
    @required this.command,
    @required this.sender,
    this.message,
  });
}
