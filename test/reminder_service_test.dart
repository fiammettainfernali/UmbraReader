// Reading reminders — "routine anchoring".
//
// The scheduling rule is the feature: an invitation is only an invitation if
// it stays quiet when there's nothing to invite you to. These tests pin the
// pure planner; the plugin call itself is a thin wrapper around it and
// no-ops where the platform channel is absent.

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra_reader/services/reminder_service.dart';

const _at = TimeOfDay(hour: 20, minute: 30);

/// 2026-07-16 is a Thursday; 18:00 is before the 20:30 reminder.
final _afternoon = DateTime(2026, 7, 16, 18);

void main() {
  group('plannedReminders', () {
    test('schedules today when the time is still ahead', () {
      final days = plannedReminders(
        at: _at,
        readToday: false,
        now: _afternoon,
      );
      expect(days.first, DateTime(2026, 7, 16, 20, 30));
    });

    test('skips today once the reader has already read', () {
      // The anti-nag rule: there is nothing to invite them to.
      final days = plannedReminders(at: _at, readToday: true, now: _afternoon);
      expect(days.first, DateTime(2026, 7, 17, 20, 30));
    });

    test('skips today when the chosen time has already passed', () {
      final days = plannedReminders(
        at: _at,
        readToday: false,
        now: DateTime(2026, 7, 16, 22),
      );
      expect(days.first, DateTime(2026, 7, 17, 20, 30));
    });

    test('does not fire for a time that just passed this minute', () {
      final days = plannedReminders(
        at: _at,
        readToday: false,
        now: DateTime(2026, 7, 16, 20, 30),
      );
      expect(
        days.first,
        DateTime(2026, 7, 17, 20, 30),
        reason: 'scheduling into the present would fire immediately',
      );
    });

    test('covers the horizon, one invitation per day', () {
      final days = plannedReminders(
        at: _at,
        readToday: false,
        now: _afternoon,
      );
      expect(days, hasLength(kReminderHorizonDays));
      for (var i = 1; i < days.length; i++) {
        expect(
          days[i].difference(days[i - 1]),
          const Duration(days: 1),
          reason: 'reminders must be exactly a day apart',
        );
      }
    });

    test('a skipped today costs a day of runway, not a duplicate', () {
      final days = plannedReminders(at: _at, readToday: true, now: _afternoon);
      expect(days, hasLength(kReminderHorizonDays - 1));
      expect(days.toSet(), hasLength(days.length));
    });

    test('every reminder lands at the chosen time', () {
      final days = plannedReminders(
        at: const TimeOfDay(hour: 7, minute: 5),
        readToday: false,
        now: _afternoon,
      );
      for (final d in days) {
        expect(d.hour, 7);
        expect(d.minute, 5);
      }
    });

    test('rolls across a month boundary', () {
      final days = plannedReminders(
        at: _at,
        readToday: false,
        now: DateTime(2026, 7, 30, 12),
        horizonDays: 4,
      );
      expect(days.map((d) => '${d.month}-${d.day}'), [
        '7-30',
        '7-31',
        '8-1',
        '8-2',
      ]);
    });

    test('rolls across a year boundary', () {
      final days = plannedReminders(
        at: _at,
        readToday: false,
        now: DateTime(2026, 12, 31, 12),
        horizonDays: 2,
      );
      expect(days.map((d) => d.year), [2026, 2027]);
    });

    test('an early-morning reminder still schedules today', () {
      final days = plannedReminders(
        at: const TimeOfDay(hour: 7, minute: 0),
        readToday: false,
        now: DateTime(2026, 7, 16, 6),
        horizonDays: 1,
      );
      expect(days.single, DateTime(2026, 7, 16, 7));
    });
  });

  group('settings', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      ReminderService().resetForTest();
    });

    test('reminders are off until asked for', () async {
      expect(await ReminderService().isEnabled(), isFalse);
    });

    test('an unset time falls back to the default', () async {
      expect(await ReminderService().time(), ReminderService.defaultTime);
    });

    test('the chosen time round-trips', () async {
      await ReminderService().setTime(const TimeOfDay(hour: 7, minute: 5));
      expect(
        await ReminderService().time(),
        const TimeOfDay(hour: 7, minute: 5),
      );
    });

    test('enabling without a notification channel stays off', () async {
      // No plugin in a unit test, so nothing could ever be delivered. The
      // switch must not claim otherwise.
      expect(await ReminderService().setEnabled(true), isFalse);
      expect(await ReminderService().isEnabled(), isFalse);
    });

    test('disabling is always honoured', () async {
      expect(await ReminderService().setEnabled(false), isFalse);
      expect(await ReminderService().isEnabled(), isFalse);
    });

    test('refresh is a no-op rather than a crash without a plugin', () async {
      await expectLater(ReminderService().refresh(), completes);
    });
  });

  group('copy', () {
    // The design principle, made testable: invitations, not obligations.
    test('no invitation leans on streaks, guilt, or urgency', () {
      const banned = [
        'streak',
        'don\'t lose',
        'keep it up',
        'you haven\'t',
        'missed',
        'behind',
        'still',
        'need to',
        'should',
        'must',
        '!',
      ];
      for (final line in ReminderService.invitations) {
        for (final word in banned) {
          expect(
            line.toLowerCase(),
            isNot(contains(word)),
            reason: '"$line" pressures the reader with "$word"',
          );
        }
      }
    });

    test('there are enough to not become wallpaper', () {
      expect(ReminderService.invitations.length, greaterThanOrEqualTo(3));
      expect(
        ReminderService.invitations.toSet(),
        hasLength(ReminderService.invitations.length),
      );
    });
  });
}
