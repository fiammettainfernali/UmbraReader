import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:umbra_reader/services/server_route.dart';
import 'package:umbra_reader/services/settings_service.dart';

const first = 'https://pc.tail1234.ts.net';
const second = 'http://192.168.4.77:8765';

OpdsSettings both({String one = first, String two = second}) => OpdsSettings(
  baseUrl: one,
  secondUrl: two,
  username: 'me',
  password: 'pw',
);

/// A network where each address either answers, refuses to connect, or hangs.
class Net {
  final Map<String, String> state = {first: 'up', second: 'up'};
  final asked = <Uri>[];

  http.Client client() => MockClient((request) async {
    asked.add(request.url);
    final origin = request.url.origin;
    final key = state.keys.firstWhere(
      (k) => Uri.parse(k).origin == origin,
      orElse: () => '',
    );
    switch (state[key]) {
      case 'up':
        return http.Response('<feed/>', 200);
      case 'hang':
        return Completer<http.Response>().future;
      default:
        throw const SocketException('Network is unreachable');
    }
  });
}

void main() {
  late Net net;
  late ServerRoute route;
  late StreamController<Object?> network;

  setUp(() {
    net = Net();
    network = StreamController<Object?>.broadcast();
    route = ServerRoute(client: net.client, networkChanges: () => network.stream);
  });

  tearDown(() => network.close());

  test('a network change has both asked again before the next request', () async {
    final settings = both();
    await route.ready(settings);
    net.state[first] = 'down'; // Tailscale switched off...
    network.add('vpn gone'); // ...which the phone announces
    await Future<void>.delayed(Duration.zero);
    final clock = Stopwatch()..start();
    expect(await route.ready(settings), second);
    expect(clock.elapsed, lessThan(ServerRoute.preferFirstFor + const Duration(seconds: 1)));
    net.state[first] = 'up'; // and back on
    network.add('vpn back');
    await Future<void>.delayed(Duration.zero);
    expect(await route.ready(settings), first, reason: 'straight back, not in five minutes');
  });

  test('with one address there is nothing to decide', () async {
    final one = both(two: '');
    expect(await route.ready(one), first);
    expect(route.baseFor(one), first);
    expect(net.asked, isEmpty);
  });

  test('both answering, the first is used', () async {
    expect(await route.ready(both()), first);
    expect(route.onSecond, isFalse);
  });

  test('the first not answering, the second is used and said so', () async {
    net.state[first] = 'down';
    expect(await route.ready(both()), second);
    expect(route.onSecond, isTrue);
    expect(route.using.value, second);
  });

  test('a first address that hangs gives way to the second', () async {
    net.state[first] = 'hang';
    final clock = Stopwatch()..start();
    expect(await route.ready(both()), second);
    expect(
      clock.elapsed,
      lessThan(ServerRoute.preferFirstFor + const Duration(seconds: 1)),
    );
  });

  test('neither answering stays on the first, so the error names it', () async {
    net.state[first] = 'down';
    net.state[second] = 'down';
    expect(await route.ready(both()), first);
  });

  test('a wrong password still counts as the right computer', () async {
    final strict = ServerRoute(
      client: () => MockClient((_) async => http.Response('', 401)),
    );
    expect(await strict.ready(both()), first);
  });

  test('asking both carries the password', () async {
    await route.ready(both());
    expect(net.asked.map((u) => u.path), everyElement('/opds'));
  });

  test('the choice is made once, not per request', () async {
    final settings = both();
    await Future.wait([for (var i = 0; i < 5; i++) route.ready(settings)]);
    await route.ready(settings);
    expect(net.asked.length, 2, reason: 'one question to each address');
  });

  test('a request that cannot reach the first is sent to the second', () async {
    final settings = both();
    await route.ready(settings);
    net.state[first] = 'down'; // Tailscale switched off
    final tried = <String>[];
    final result = await route.run(settings, (base) async {
      tried.add(base);
      if (net.state[base] != 'up') throw const SocketException('no route');
      return 'ok from $base';
    }, unreachable: (e) => e is SocketException);
    expect(result, 'ok from $second');
    expect(tried, [first, second]);
  });

  test('an answer from the computer is not sent elsewhere', () async {
    final settings = both();
    final tried = <String>[];
    await expectLater(
      route.run(settings, (base) async {
        tried.add(base);
        throw StateError('HTTP 500');
      }, unreachable: (e) => e is SocketException),
      throwsStateError,
    );
    expect(tried, [first]);
  });

  test('when the same address wins again, the failure stands', () async {
    final settings = both();
    await route.ready(settings);
    expect(await route.recover(settings, first), isFalse);
  });

  test('back on the first once it answers again', () async {
    final settings = both();
    net.state[first] = 'down';
    await route.ready(settings);
    net.state[first] = 'up';
    expect(await route.recover(settings, second), isTrue);
    expect(route.baseFor(settings), first);
  });

  test('changing the addresses starts over', () async {
    net.state[first] = 'down';
    await route.ready(both());
    expect(route.baseFor(both(two: '')), first);
    expect(route.onSecond, isFalse);
  });

  group('links', () {
    setUp(() async {
      net.state[first] = 'down';
      await route.ready(both());
    });

    test('are stored under the first address', () {
      expect(route.canonical('$second/opds/cover/7'), '$first/opds/cover/7');
      expect(route.canonical('$first/opds/cover/7'), '$first/opds/cover/7');
    });

    test('are fetched from the address in use', () {
      expect(route.link('$first/epub/7/a.epub'), '$second/epub/7/a.epub');
    });

    test('elsewhere are left alone', () {
      expect(route.link('https://example.com/x'), 'https://example.com/x');
      expect(
        route.link('${first}0/x'),
        '${first}0/x',
        reason: 'a longer host is a different host',
      );
    });
  });
}
