import 'dart:async';

import 'package:spotify_sdk/models/player_state.dart';
import 'package:spotify_sdk/models/track.dart';
import 'package:spotify_sdk/spotify_sdk.dart';

class SpotifyTrackState {
  final String title;
  final String artist;
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final bool isActive;

  const SpotifyTrackState({
    required this.title,
    required this.artist,
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.isActive,
  });

  factory SpotifyTrackState.unavailable() => const SpotifyTrackState(
        title: 'Spotify',
        artist: 'Not connected',
        position: Duration.zero,
        duration: Duration.zero,
        isPlaying: false,
        isActive: false,
      );
}

class SpotifyPlaybackService {
  SpotifyPlaybackService({
    required this.clientId,
    required this.redirectUri,
  });

  final String clientId;
  final String redirectUri;

  final StreamController<SpotifyTrackState> _stateController =
      StreamController<SpotifyTrackState>.broadcast();
  Stream<SpotifyTrackState> get playbackStream => _stateController.stream;

  StreamSubscription<PlayerState>? _playerStateSub;
  SpotifyTrackState? _latestState;
  bool _connecting = false;
  bool _connected = false;

  bool get isConnected => _connected;
  SpotifyTrackState? get lastKnownState => _latestState;

  Future<void> connect() async {
    if (_connected || _connecting) return;
    _connecting = true;
    try {
      print('🎵 [Spotify] Attempting to connect...');
      print('🎵 [Spotify] Client ID: $clientId');
      print('🎵 [Spotify] Redirect URI: $redirectUri');

      // Step 1: Get authentication token first
      print('🎵 [Spotify] Step 1: Getting authentication token...');
      try {
        await SpotifySdk.getAuthenticationToken(
          clientId: clientId,
          redirectUrl: redirectUri,
          scope: 'app-remote-control, '
              'user-modify-playback-state, '
              'playlist-read-private, '
              'playlist-read-collaborative, '
              'user-read-playback-state, '
              'user-read-currently-playing',
        );
        print('🎵 [Spotify] Auth token obtained: ✓');
      } catch (authError, authStack) {
        print('❌ [Spotify] Auth error: $authError');
        print('❌ [Spotify] Auth stack: $authStack');
        // Continue anyway - connectToSpotifyRemote might handle auth itself
      }

      // Step 2: Connect to Spotify Remote
      print('🎵 [Spotify] Step 2: Connecting to Spotify Remote...');
      _connected = await SpotifySdk.connectToSpotifyRemote(
        clientId: clientId,
        redirectUrl: redirectUri,
      );

      print('🎵 [Spotify] Connection result: $_connected');

      if (_connected) {
        print(
            '🎵 [Spotify] Successfully connected! Subscribing to player state...');
        _playerStateSub ??= SpotifySdk.subscribePlayerState().listen(
            _handlePlayerState, onError: (Object error, StackTrace stack) {
          print('❌ [Spotify] Player state error: $error');
          print('❌ [Spotify] Stack trace: $stack');
          _stateController.addError(error, stack);
          _connected = false;
          _playerStateSub?.cancel();
          _playerStateSub = null;
        });
      } else {
        print('❌ [Spotify] Failed to connect (returned false)');
      }
    } catch (e, stack) {
      print('❌ [Spotify] Connection error: $e');
      print('❌ [Spotify] Stack trace: $stack');
      _connected = false;
      _stateController.addError(e, stack);
    } finally {
      _connecting = false;
    }
  }

  void _handlePlayerState(PlayerState state) {
    final Track? track = state.track;
    if (track == null) {
      _latestState = SpotifyTrackState.unavailable();
      _stateController.add(_latestState!);
      return;
    }

    final artistName = track.artist.name ?? track.artist.uri ?? '';
    _latestState = SpotifyTrackState(
      title: track.name ?? 'Unknown track',
      artist: artistName.isEmpty ? 'Unknown artist' : artistName,
      position: Duration(milliseconds: state.playbackPosition),
      duration: Duration(milliseconds: track.duration ?? 0),
      isPlaying: !state.isPaused,
      isActive: true,
    );
    _stateController.add(_latestState!);
  }

  Future<void> togglePlayPause({required bool isPlaying}) async {
    await connect();
    if (!_connected) return;
    if (isPlaying) {
      await SpotifySdk.pause();
    } else {
      await SpotifySdk.resume();
    }
  }

  Future<void> skipNext() async {
    await connect();
    if (_connected) {
      await SpotifySdk.skipNext();
    }
  }

  Future<void> skipPrevious() async {
    await connect();
    if (_connected) {
      await SpotifySdk.skipPrevious();
    }
  }

  Future<void> seekTo(Duration position) async {
    await connect();
    if (_connected) {
      await SpotifySdk.seekTo(positionedMilliseconds: position.inMilliseconds);
    }
  }

  void dispose() {
    _playerStateSub?.cancel();
    _stateController.close();
  }
}
