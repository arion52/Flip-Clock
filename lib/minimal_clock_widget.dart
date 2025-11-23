import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

class MinimalClockWidget extends StatefulWidget {
  const MinimalClockWidget({super.key});

  @override
  State<MinimalClockWidget> createState() => _MinimalClockWidgetState();
}

class _MinimalClockWidgetState extends State<MinimalClockWidget>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late DateTime _now;
  Timer? _timer;
  bool _is24 = false; // default to 12-hour display
  late final AnimationController _blinkController;
  // blink minimum opacity (1.0 -> _blinkMinOpacity). Controlled via settings.
  double _blinkMinOpacity = 0.6;
  bool _dimmed = false;
  Timer? _dimTimer;
  // battery_plus removed; we no longer track plug state here
  // session start tracking for elapsed desk time
  DateTime _sessionStart = DateTime.now();
  // dim timeout in minutes (0 = disabled)
  double _dimTimeoutMinutes = 3.0;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    WidgetsBinding.instance.addObserver(this);
    // align timer to minute boundary for efficiency
    _startTimer();
    // blinking colon animation (runs without setState each second)
    // We drive opacity manually from the controller to allow runtime
    // adjustments of the blink intensity (min opacity).
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _resetDim();

    // battery_plus removed: dimming always active (no plug-state override)
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
    final size = MediaQuery.of(context).size;
    // make font size relative to the smallest dimension (user requested 0.3 * base)
    final base = (size.width < size.height ? size.width : size.height) * 0.3;

    final minutes = _now.minute.toString().padLeft(2, '0');
    int displayHour = _now.hour;
    if (!_is24) {
      displayHour = _now.hour % 12;
      if (displayHour == 0) displayHour = 12;
    }
    final hours = displayHour.toString().padLeft(2, '0');

    // auto-dim during night hours (UI-only): darker text color
    final hour = _now.hour;
    final platformDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final isNight = platformDark || hour >= 22 || hour < 7;
    // Use pure white for all text per user request
    const timeColor = Colors.white;
    const dateColor = Colors.white;

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
                    color: timeColor,
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
                      color: timeColor,
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
                    color: timeColor,
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
                      color: timeColor.withAlpha((0.55 * 255).toInt()),
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
            color: dateColor,
            fontSize: base * 0.12,
            fontWeight: FontWeight.w200,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: GestureDetector(
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
                  liveTimer ??=
                      Timer.periodic(const Duration(seconds: 10), (_) {
                    if (!mounted) return;
                    setC(() {});
                  });
                  return WillPopScope(
                    onWillPop: () async {
                      liveTimer?.cancel();
                      return true;
                    },
                    child: Dialog(
                      backgroundColor: Colors.black87,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 20.0, horizontal: 24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Elapsed desk time',
                              style: TextStyle(color: timeColor, fontSize: 16),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _elapsedString(),
                              style: const TextStyle(
                                  color: timeColor,
                                  fontSize: 28,
                                  fontFamily: 'JetBrainsMono'),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Double-tap anywhere to reset',
                              style: TextStyle(color: dateColor, fontSize: 12),
                            ),
                            const SizedBox(height: 6),
                            TextButton(
                              onPressed: () {
                                liveTimer?.cancel();
                                Navigator.of(ctx).pop();
                              },
                              child: const Text(
                                'Close',
                                style: TextStyle(
                                    color: Color.fromARGB(120, 255, 255, 255)),
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
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 400),
            opacity: _dimmed ? 0.25 : 1.0,
            child: clockColumn,
          ),
        ),
      ),
    );
  }

  void _showSettingsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey[900],
      builder: (ctx) {
        return StatefulBuilder(builder: (c, setC) {
          return Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(height: 4, width: 36, color: Colors.white24),
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
