import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'services/spotify_service.dart';

class MinimalClockWidget extends StatefulWidget {
  const MinimalClockWidget({super.key});

  @override
  State<MinimalClockWidget> createState() => _MinimalClockWidgetState();
}

class _MinimalClockWidgetState extends State<MinimalClockWidget>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const Color _timeColor = Colors.white;
  static const Color _dateColor = Colors.white;

  late DateTime _now;
  Timer? _timer;
  bool _is24 = false; // default to 12-hour display
  late final AnimationController _blinkController;
  // blink minimum opacity (1.0 -> _blinkMinOpacity). Controlled via settings.
  double _blinkMinOpacity = 0.6;
  bool _dimmed = false;
  Timer? _dimTimer;
  // session start tracking for elapsed desk time
  DateTime _sessionStart = DateTime.now();
  // dim timeout in minutes (0 = disabled)
  double _dimTimeoutMinutes = 3.0;

  late final SpotifyPlaybackService _spotifyService;
  StreamSubscription<SpotifyTrackState>? _spotifySub;
  SpotifyTrackState? _spotifyState;

  MediaTrack get _uiTrack => _spotifyState == null
      ? const MediaTrack(
          title: 'Spotify',
          artist: 'Connect to start playback',
          duration: Duration.zero,
        )
      : MediaTrack(
          title: _spotifyState!.title,
          artist: _spotifyState!.artist,
          duration: _spotifyState!.duration,
        );

  Duration get _uiPosition => _spotifyState?.position ?? Duration.zero;
  bool get _uiPlaying => _spotifyState?.isPlaying ?? false;
  bool get _uiControlsEnabled => _spotifyState?.isActive ?? false;
  bool get _uiCanScrub =>
      _uiControlsEnabled && (_spotifyState?.duration.inMilliseconds ?? 0) > 0;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    WidgetsBinding.instance.addObserver(this);
    // align timer to minute boundary for efficiency
    _startTimer();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _resetDim();
    _spotifyService = SpotifyPlaybackService(
      clientId: '47686d20ae4a416caa61bff5accef7ef',
      redirectUri: 'spotify-sdk://auth',
    );
    _spotifySub = _spotifyService.playbackStream.listen(
      (state) {
        if (!mounted) return;
        setState(() => _spotifyState = state);
      },
      onError: (error, stackTrace) {
        print('❌ [UI] Spotify playback stream error: $error');
        print('❌ [UI] Stack trace: $stackTrace');
      },
    );
    Future.microtask(() => _spotifyService.connect());
  }

  void _tick() {
    final now = DateTime.now();
    if (now.minute != _now.minute || now.hour != _now.hour) {
      setState(() {
        _now = now;
      });
    }
  }

  void _startTimer() {
    _timer?.cancel();
    final now = DateTime.now();
    // compute milliseconds until next minute boundary
    final msUntilNextMinute = (60 - now.second) * 1000 - now.millisecond;
    // schedule a one-shot timer to align, then periodic minutes
    _timer = Timer(Duration(milliseconds: msUntilNextMinute), () {
      _tick();
      _timer = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _blinkController.dispose();
    _dimTimer?.cancel();
    _spotifySub?.cancel();
    _spotifyService.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // resync time and restart minute-aligned timer
      setState(() {
        _now = DateTime.now();
      });
      _startTimer();
      _resetDim();
      Future.microtask(() => _spotifyService.connect());
    }
  }

  void _resetDim() {
    _dimTimer?.cancel();
    if (_dimmed) setState(() => _dimmed = false);
    if (_dimTimeoutMinutes <= 0) return; // dim disabled
    _dimTimer = Timer(Duration(minutes: _dimTimeoutMinutes.toInt()), () {
      if (!mounted) return;
      setState(() => _dimmed = true);
    });
  }

  String _elapsedString() {
    final dur = DateTime.now().difference(_sessionStart);
    final hours = dur.inHours;
    final minutes = dur.inMinutes % 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, viewport) {
        final width = viewport.maxWidth;
        final height = viewport.maxHeight;
        final shortestSide = math.min(width, height);
        final isTablet = shortestSide >= 600;
        final isWide = width > height * 1.1;

        final horizontalPadding =
            (width * (isTablet ? 0.07 : 0.05)).clamp(16.0, 80.0).toDouble();
        final verticalPadding = (height * 0.08).clamp(12.0, 72.0).toDouble();

        final clockMaxWidth = width * (isWide ? 0.55 : 0.9);
        final clockMaxHeight = height * (isWide ? 0.75 : 0.55);

        final clock = _buildClock(clockMaxWidth, clockMaxHeight, context);
        final snapshot = _buildSnapshot(isTablet, isWide, width);

        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: verticalPadding,
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: isWide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(child: Center(child: clock)),
                                  SizedBox(width: math.min(width * 0.03, 48.0)),
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: math.min(width * 0.26, 360.0),
                                    ),
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: snapshot,
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                children: [
                                  Expanded(child: Center(child: clock)),
                                  SizedBox(height: height * 0.04),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: snapshot,
                                  ),
                                ],
                              ),
                      ),
                      SizedBox(height: isTablet ? 28 : 20),
                      MediaControlsBar(
                        track: _uiTrack,
                        position: _uiPosition,
                        isPlaying: _uiPlaying,
                        isTablet: isTablet,
                        onPlayPause: _uiControlsEnabled
                            ? () => unawaited(_handlePlayPause())
                            : null,
                        onNext: _uiControlsEnabled
                            ? () => unawaited(_advanceTrack(delta: 1))
                            : null,
                        onPrev: _uiControlsEnabled
                            ? () => unawaited(_advanceTrack(delta: -1))
                            : null,
                        onScrub: _uiCanScrub
                            ? (value) => unawaited(_handleScrub(value))
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
              IgnorePointer(
                ignoring: !_dimmed,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 400),
                  opacity: _dimmed ? 1.0 : 0.0,
                  child: Container(
                    color: Colors.black.withOpacity(0.7),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildClock(double maxWidth, double maxHeight, BuildContext context) {
    final clockDimension = math.min(maxWidth, maxHeight);
    final base = (clockDimension * 0.45).clamp(72.0, clockDimension).toDouble();
    final minutes = _now.minute.toString().padLeft(2, '0');
    int displayHour = _now.hour;
    if (!_is24) {
      displayHour = _now.hour % 12;
      if (displayHour == 0) displayHour = 12;
    }
    final hours = displayHour.toString().padLeft(2, '0');

    final clockColumn = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // hours with AnimatedSwitcher for smooth crossfade on change
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 900),
                transitionBuilder: (child, anim) =>
                    FadeTransition(opacity: anim, child: child),
                child: Text(
                  hours,
                  key: ValueKey('h$hours'),
                  style: TextStyle(
                    fontFamily: 'JetBrainsMono',
                    color: _timeColor,
                    fontSize: base,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 1.0,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              // blinking colon wrapped in TickerMode so it stops when dimmed
              TickerMode(
                enabled: !_dimmed,
                child: AnimatedBuilder(
                  animation: _blinkController,
                  builder: (context, child) {
                    final t =
                        Curves.easeInOut.transform(_blinkController.value);
                    final opacity = lerpDouble(1.0, _blinkMinOpacity, t) ?? 1.0;
                    return Opacity(opacity: opacity, child: child);
                  },
                  child: Text(
                    ':',
                    key: const Key('minimal_clock_colon'),
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      color: _timeColor,
                      fontSize: base,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.0,
                    ),
                  ),
                ),
              ),
              // minutes with AnimatedSwitcher for smooth crossfade on change
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 900),
                transitionBuilder: (child, anim) =>
                    FadeTransition(opacity: anim, child: child),
                child: Text(
                  minutes,
                  key: ValueKey('m$minutes'),
                  style: TextStyle(
                    fontFamily: 'JetBrainsMono',
                    color: _timeColor,
                    fontSize: base,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 1.0,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              // AM/PM indicator for 12-hour mode
              if (!_is24) ...[
                Padding(
                  // align optical baseline with digits so AM/PM doesn't look hung
                  padding: EdgeInsets.only(bottom: base * 0.3),
                  child: Text(
                    _now.hour >= 12 ? 'PM' : 'AM',
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      color: _timeColor.withAlpha((0.55 * 255).toInt()),
                      fontSize: base * 0.12,
                      fontWeight: FontWeight.w300,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        // small date line
        Text(
          _formatDate(_now),
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            color: _dateColor,
            fontSize: base * 0.12,
            fontWeight: FontWeight.w200,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );

    final clockBody = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      ),
      child: FittedBox(fit: BoxFit.scaleDown, child: clockColumn),
    );

    return GestureDetector(
      onTap: _resetDim,
      onLongPress: () async {
        // show elapsed desk time overlay
        _resetDim();
        await showDialog<void>(
          context: context,
          barrierDismissible: true,
          builder: (ctx) {
            Timer? liveTimer;
            return StatefulBuilder(builder: (c, setC) {
              // update every 10s while dialog shown so value stays reasonably fresh
              liveTimer ??= Timer.periodic(const Duration(seconds: 10), (_) {
                if (!mounted) return;
                setC(() {});
              });
              return WillPopScope(
                onWillPop: () async {
                  liveTimer?.cancel();
                  return true;
                },
                child: Dialog(
                  backgroundColor: Colors.black.withOpacity(0.9),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 20.0, horizontal: 24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Elapsed desk time',
                          style: TextStyle(color: _timeColor, fontSize: 16),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _elapsedString(),
                          style: const TextStyle(
                            color: _timeColor,
                            fontSize: 28,
                            fontFamily: 'JetBrainsMono',
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Double-tap anywhere to reset',
                          style: TextStyle(color: _dateColor, fontSize: 12),
                        ),
                        const SizedBox(height: 6),
                        TextButton(
                          onPressed: () {
                            liveTimer?.cancel();
                            Navigator.of(ctx).pop();
                          },
                          child: Text(
                            'Close',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.47),
                            ),
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              );
            });
          },
        );
      },
      onDoubleTap: () {
        // toggle 12/24 display on double-tap
        setState(() {
          _is24 = !_is24;
          _now = DateTime.now();
        });
        _resetDim();
      },
      onVerticalDragEnd: (details) {
        // swipe up (negative dy) to open settings
        if (details.primaryVelocity != null &&
            details.primaryVelocity! < -300) {
          _showSettingsSheet(context);
        }
      },
      child: clockBody,
    );
  }

  Widget _buildSnapshot(
      bool isTablet, bool isWideLayout, double viewportWidth) {
    final headlineStyle = TextStyle(
      color: Colors.white.withOpacity(0.6),
      fontSize: isWideLayout ? 13 : 12,
      letterSpacing: 2.0,
    );
    final valueStyle = TextStyle(
      color: Colors.white,
      fontSize: isTablet ? 24 : 20,
      fontFamily: 'JetBrainsMono',
      fontWeight: FontWeight.w400,
    );

    final entries = [
      MapEntry('Session', _elapsedString()),
      MapEntry('Display', _is24 ? '24-hour' : '12-hour'),
      MapEntry(
        'Dim timeout',
        _dimTimeoutMinutes <= 0 ? 'Off' : '${_dimTimeoutMinutes.round()} min',
      ),
      MapEntry('Brightness', _dimmed ? 'Dimmed' : 'Active'),
    ];

    final maxWidth = math.min(
      viewportWidth * (isWideLayout ? 0.24 : 0.62),
      360.0,
    );

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('SNAPSHOT', style: headlineStyle),
          const SizedBox(height: 18),
          for (final entry in entries) ...[
            Text(
              entry.key.toUpperCase(),
              style: headlineStyle.copyWith(fontSize: 11),
            ),
            const SizedBox(height: 4),
            Text(entry.value, style: valueStyle),
            const SizedBox(height: 14),
          ],
          Container(
            height: 1,
            color: Colors.white.withOpacity(0.12),
          ),
          const SizedBox(height: 12),
          Text(
            _dimmed
                ? 'Display dimmed — tap anywhere to brighten.'
                : 'Display active — long-press for more stats.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  void _showSettingsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (ctx) {
        return StatefulBuilder(builder: (c, setC) {
          return Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  height: 4,
                  width: 36,
                  color: Colors.white.withOpacity(0.24),
                ),
                const SizedBox(height: 12),
                ListTile(
                  title: const Text('24-hour clock'),
                  trailing: Switch(
                    value: _is24,
                    onChanged: (v) => setState(() {
                      _is24 = v;
                    }),
                  ),
                ),
                ListTile(
                  title: const Text('Blink intensity'),
                  subtitle: Slider(
                    min: 0.2,
                    max: 1.0,
                    divisions: 16,
                    value: _blinkMinOpacity,
                    onChanged: (v) => setState(() {
                      _blinkMinOpacity = v;
                    }),
                  ),
                ),
                ListTile(
                  title: const Text('Dim timeout (minutes)'),
                  subtitle: Slider(
                    min: 0.0,
                    max: 30.0,
                    divisions: 30,
                    value: _dimTimeoutMinutes,
                    onChanged: (v) => setState(() {
                      // update dim behavior by cancelling and rescheduling with new duration
                      _dimTimeoutMinutes = v;
                      _dimTimer?.cancel();
                      if (v <= 0) {
                        // disable dim
                        _dimTimer = null;
                        _dimmed = false;
                      } else {
                        _dimTimer = Timer(Duration(minutes: v.toInt()), () {
                          if (!mounted) return;
                          setState(() => _dimmed = true);
                        });
                      }
                    }),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ElevatedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Done'),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            // reset session and close
                            _sessionStart = DateTime.now();
                          });
                        },
                        child: const Text('Reset session'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  Future<void> _handlePlayPause() async {
    if (_spotifyState == null) {
      await _spotifyService.connect();
      return;
    }
    await _spotifyService.togglePlayPause(
      isPlaying: _spotifyState?.isPlaying ?? false,
    );
    _resetDim();
  }

  Future<void> _advanceTrack({int delta = 1}) async {
    if (_spotifyState == null) {
      await _spotifyService.connect();
      return;
    }
    if (delta >= 0) {
      await _spotifyService.skipNext();
    } else {
      await _spotifyService.skipPrevious();
    }
    _resetDim();
  }

  Future<void> _handleScrub(double fraction) async {
    final state = _spotifyState;
    if (state == null || state.duration.inMilliseconds <= 0) return;
    final safeFraction = fraction.clamp(0.0, 1.0).toDouble();
    final newPosition = Duration(
      milliseconds: (state.duration.inMilliseconds * safeFraction).round(),
    );
    await _spotifyService.seekTo(newPosition);
    _resetDim();
  }

  String _formatDate(DateTime d) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final w = weekdays[d.weekday - 1];
    final m = months[d.month - 1];
    return '$w ${d.day} $m';
  }
}

class MediaTrack {
  final String title;
  final String artist;
  final Duration duration;

  const MediaTrack({
    required this.title,
    required this.artist,
    required this.duration,
  });
}

class MediaControlsBar extends StatelessWidget {
  final MediaTrack track;
  final Duration position;
  final bool isPlaying;
  final bool isTablet;
  final VoidCallback? onPlayPause;
  final VoidCallback? onNext;
  final VoidCallback? onPrev;
  final ValueChanged<double>? onScrub;

  const MediaControlsBar({
    super.key,
    required this.track,
    required this.position,
    required this.isPlaying,
    required this.isTablet,
    this.onPlayPause,
    this.onNext,
    this.onPrev,
    this.onScrub,
  });

  @override
  Widget build(BuildContext context) {
    final totalMs = track.duration.inMilliseconds;
    final progress = totalMs == 0
        ? 0.0
        : (position.inMilliseconds / totalMs).clamp(0.0, 1.0);
    final labelStyle = TextStyle(
      color: Colors.white.withOpacity(0.6),
      fontSize: isTablet ? 13 : 11,
      letterSpacing: 1.6,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isTablet ? 22 : 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artist.toUpperCase(),
                    style: labelStyle,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.music_note_rounded,
              color: Colors.white,
              size: isTablet ? 26 : 22,
            ),
          ],
        ),
        SizedBox(height: isTablet ? 12 : 10),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: RoundSliderThumbShape(
              enabledThumbRadius: isTablet ? 9 : 7,
            ),
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white.withOpacity(0.2),
            thumbColor: Colors.white,
            overlayShape: SliderComponentShape.noOverlay,
          ),
          child: Slider(
            value: progress,
            onChanged: (onScrub == null || totalMs == 0) ? null : onScrub,
            min: 0,
            max: 1,
          ),
        ),
        SizedBox(height: isTablet ? 8 : 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatDuration(position),
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontFamily: 'JetBrainsMono',
                fontSize: isTablet ? 14 : 12,
              ),
            ),
            Text(
              _formatDuration(track.duration),
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontFamily: 'JetBrainsMono',
                fontSize: isTablet ? 14 : 12,
              ),
            ),
          ],
        ),
        SizedBox(height: isTablet ? 12 : 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: isTablet ? 32 : 24,
          runSpacing: 10,
          children: [
            IconButton(
              onPressed: onPrev,
              icon: const Icon(Icons.skip_previous_rounded),
              iconSize: isTablet ? 40 : 34,
              color: Colors.white,
            ),
            IconButton(
              onPressed: onPlayPause,
              icon: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              ),
              iconSize: isTablet ? 46 : 40,
              color: Colors.white,
            ),
            IconButton(
              onPressed: onNext,
              icon: const Icon(Icons.skip_next_rounded),
              iconSize: isTablet ? 40 : 34,
              color: Colors.white,
            ),
          ],
        ),
      ],
    );
  }

  static String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes =
        duration.inMinutes.remainder(60).abs().toString().padLeft(2, '0');
    final seconds =
        duration.inSeconds.remainder(60).abs().toString().padLeft(2, '0');
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}
