import 'dart:async';

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
  late final Animation<double> _blinkAnimation;
  bool _dimmed = false;
  Timer? _dimTimer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    WidgetsBinding.instance.addObserver(this);
    // align timer to minute boundary for efficiency
    _startTimer();
    // blinking colon animation (runs without setState each second)
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    _blinkAnimation = Tween<double>(begin: 1.0, end: 0.25).animate(
      CurvedAnimation(parent: _blinkController, curve: Curves.easeInOut),
    );
    _resetDim();
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
    setState(() {
      _dimmed = false;
    });
    _dimTimer = Timer(const Duration(minutes: 3), () {
      setState(() {
        _dimmed = true;
      });
    });
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
    final isNight = hour >= 22 || hour < 7;
    const defaultTimeColor = Color(0xFFE6E6E6);
    final timeColor = isNight
        ? defaultTimeColor.withAlpha((0.1 * 255).toInt())
        : defaultTimeColor;
    final dateColor =
        isNight ? const Color(0xFF777777) : const Color(0xFF888888);

    final clockColumn = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                hours,
                key: const Key('minimal_clock_hours'),
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  color: timeColor,
                  fontSize: base,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 1.0,
                ),
              ),
              // blinking colon using FadeTransition driven by controller
              FadeTransition(
                opacity: _blinkAnimation,
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
              Text(
                minutes,
                key: const Key('minimal_clock_minutes'),
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  color: timeColor,
                  fontSize: base,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 1.0,
                ),
              ),
              // AM/PM indicator for 12-hour mode
              if (!_is24) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: EdgeInsets.only(bottom: base * 0.55),
                  child: Text(
                    _now.hour >= 12 ? 'PM' : 'AM',
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      color: timeColor.withAlpha((0.9 * 255).toInt()),
                      fontSize: base * 0.11,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        // small date line
        Text(
          _formatDate(_now),
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            color: dateColor,
            fontSize: base * 0.12,
            fontWeight: FontWeight.w300,
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
          onLongPress: () {
            // toggle 12/24 on long press
            setState(() {
              _is24 = !_is24;
              _now = DateTime.now();
            });
            _resetDim();
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
