// The pagination invariant under a real font stack.
//
// The host suite runs this same set of cases, but `flutter test` renders with
// a stub font whose glyphs are all one width — measure and render can agree
// there and still disagree on a device. This runs the identical cases through
// the platform's own fonts, which is the only place the Android/iOS split can
// actually show up.
//
// Needs a device:  flutter test integration_test/pagination_overflow_test.dart

import 'package:integration_test/integration_test.dart';

import '../test/helpers/pagination_overflow_cases.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  runPaginationOverflowCases();
}
