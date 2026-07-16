import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'reading_activity_store.dart';

/// How many days ahead reminders are scheduled.
///
/// Reminders are individually scheduled one-shots rather than one repeating
/// daily notification, because a repeat cannot skip a day (iOS matches on the
/// *time*, ignoring the date, so "start tomorrow" still fires tonight) and
/// skipping days you have already read is the whole point — see
/// [plannedReminders].
///
/// The horizon is re-armed every time the app is opened or a session is
/// recorded, so in normal use it never runs down. If someone drifts away for
/// two weeks without opening Umbra at all, the invitations stop rather than
/// following them forever, which is the behaviour an invitation implies.
/// (Well inside iOS's 64-pending-notification cap either way.)
const int kReminderHorizonDays = 14;

/// The dates a reminder should land on, given the user's chosen time.
///
/// Today is skipped when the reader has already read — there is nothing to
/// invite them to — or when the chosen time has already passed.
@visibleForTesting
List<DateTime> plannedReminders({
  required TimeOfDay at,
  required bool readToday,
  required DateTime now,
  int horizonDays = kReminderHorizonDays,
}) {
  final out = <DateTime>[];
  for (var day = 0; day < horizonDays; day++) {
    // Overflowing the day field is well-defined and rolls the month/year.
    final when = DateTime(now.year, now.month, now.day + day, at.hour, at.minute);
    if (day == 0 && (readToday || !when.isAfter(now))) continue;
    out.add(when);
  }
  return out;
}

/// Opt-in daily reading reminders.
///
/// Deliberately invitations, not obligations: the copy never mentions the
/// streak, never implies anything is at risk, and no badge is set — a red dot
/// sitting on the icon is a demand, and this app does not make demands of its
/// reader. A reminder is also never sent on a day already read.
///
/// Every plugin call degrades to a no-op where the platform channel is absent
/// (unit tests, unsupported platforms), matching how the Keychain is handled
/// in [SettingsService].
class ReminderService {
  ReminderService._();
  static final ReminderService _instance = ReminderService._();
  factory ReminderService() => _instance;

  static const _kEnabled = 'reminder_enabled';
  static const _kHour = 'reminder_hour';
  static const _kMinute = 'reminder_minute';

  /// Notification ids [_baseId] … [_baseId] + [kReminderHorizonDays] - 1 are
  /// owned by this service.
  static const _baseId = 8100;

  /// Default nudge time for someone who opts in without choosing one.
  static const defaultTime = TimeOfDay(hour: 20, minute: 30);

  /// Offered in place of "you haven't read today" or "your streak is at
  /// risk". Each says the book is there; none says the reader owes it
  /// anything.
  static const invitations = <String>[
    'Your book is where you left it.',
    'A few pages, if you feel like it.',
    'Your story is waiting — no rush.',
    'Fancy a chapter?',
    'Whenever you\'re ready.',
  ];

  final _plugin = FlutterLocalNotificationsPlugin();
  final _rng = Random();
  bool _ready = false;

  Future<bool> isEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_kEnabled) ?? false;

  Future<TimeOfDay> time() async {
    final prefs = await SharedPreferences.getInstance();
    final hour = prefs.getInt(_kHour);
    final minute = prefs.getInt(_kMinute);
    if (hour == null || minute == null) return defaultTime;
    return TimeOfDay(hour: hour, minute: minute);
  }

  /// Turns reminders on or off. Turning them on asks iOS for permission and
  /// returns false if the reader declines, leaving the setting off — an
  /// enabled switch that cannot deliver anything would be a lie.
  Future<bool> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    if (!value) {
      await prefs.setBool(_kEnabled, false);
      await refresh();
      return false;
    }
    if (!await _requestPermission()) {
      await prefs.setBool(_kEnabled, false);
      return false;
    }
    await prefs.setBool(_kEnabled, true);
    await refresh();
    return true;
  }

  Future<void> setTime(TimeOfDay value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kHour, value.hour);
    await prefs.setInt(_kMinute, value.minute);
    await refresh();
  }

  /// Rebuilds the schedule from current settings and today's reading.
  ///
  /// Safe to call often — it is how "don't nudge me on a day I've read" takes
  /// effect, so it runs on app start and whenever a session is recorded.
  Future<void> refresh() async {
    if (!await _ensureReady()) return;
    await _cancelAll();
    if (!await isEnabled()) return;

    final activity = await ReadingActivityStore().load();
    final dates = plannedReminders(
      at: await time(),
      readToday: activity.todaySeconds() > 0,
      now: DateTime.now(),
    );
    // A different opener each day, so the reminder doesn't turn into
    // wallpaper the reader stops seeing.
    final seed = _rng.nextInt(invitations.length);
    for (var i = 0; i < dates.length; i++) {
      try {
        await _plugin.zonedSchedule(
          id: _baseId + i,
          scheduledDate: tz.TZDateTime.from(dates[i], tz.local),
          title: invitations[(seed + i) % invitations.length],
          notificationDetails: const NotificationDetails(
            iOS: DarwinNotificationDetails(presentBadge: false),
          ),
          // Irrelevant on iOS; the inexact mode is the one that needs no
          // special Android permission, so it is the honest default here.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      } on Exception {
        return;
      }
    }
  }

  Future<void> _cancelAll() async {
    for (var i = 0; i < kReminderHorizonDays; i++) {
      try {
        await _plugin.cancel(id: _baseId + i);
      } on Exception {
        return;
      }
    }
  }

  Future<bool> _requestPermission() async {
    if (!await _ensureReady()) return false;
    try {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      // No plugin implementation (tests / other platforms): nothing can be
      // delivered, so report honestly rather than pretending.
      if (ios == null) return false;
      return await ios.requestPermissions(alert: true, sound: true) ?? false;
    } on Exception {
      return false;
    }
  }

  /// Initialises the plugin and the timezone database once.
  ///
  /// The catch is deliberately broad, as in [SettingsService]: an unavailable
  /// channel surfaces as `MissingPluginException`, `PlatformException`, or an
  /// `UnimplementedError` (an `Error`, not an `Exception`) depending on
  /// platform. Any failure means "reminders are unavailable here", which is a
  /// no-op, never a crash.
  Future<bool> _ensureReady() async {
    if (_ready) return true;
    try {
      tzdata.initializeTimeZones();
      // Scheduling is wall-clock local: the reader means 8:30pm where they
      // are, so the device's zone has to drive it.
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
      await _plugin.initialize(
        settings: const InitializationSettings(
          // All false: the permission prompt belongs at the moment the reader
          // opts in, not on first launch of the app.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      _ready = true;
    } catch (_) {
      _ready = false;
    }
    return _ready;
  }

  /// Test-only: forgets initialisation state.
  @visibleForTesting
  void resetForTest() => _ready = false;
}
