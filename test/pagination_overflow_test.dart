// The host run of the pagination invariant. `flutter test` renders with a
// stub font, so this proves measure and render agree with each other — not
// that they agree under a real font stack. `integration_test/` covers that.

import 'package:flutter_test/flutter_test.dart';

import 'helpers/pagination_overflow_cases.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  runPaginationOverflowCases();
}
