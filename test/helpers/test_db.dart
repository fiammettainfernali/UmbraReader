import 'package:drift/native.dart';
import 'package:umbra_reader/db/app_database.dart';

/// Swaps [AppDatabase.instance] for a fresh in-memory database, closing any
/// previous one first. Call from setUp in any test that (directly or through
/// a screen) touches a SQLite-backed store; pair with
/// `tearDown(AppDatabase.reset)`.
Future<AppDatabase> useInMemoryDatabase() async {
  await AppDatabase.reset();
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  AppDatabase.instance = db;
  return db;
}
