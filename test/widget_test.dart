// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:coalition_mobile_app/app.dart';
import 'package:coalition_mobile_app/features/auth/data/auth_controller.dart';
import 'package:coalition_mobile_app/features/auth/data/local_user_store.dart';

void main() {
  testWidgets('App renders auth gate headline', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localUserStoreProvider.overrideWith((ref) => _TestLocalUserStore()),
        ],
        child: const CoalitionApp(),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.textContaining('Coalition for Montana'), findsOneWidget);
  });
}

class _TestLocalUserStore extends LocalUserStore {
  final List<StoredUserRecord> _records = <StoredUserRecord>[];
  String? _activeUserId;

  @override
  bool get isUsingFallbackStore => false;

  @override
  Future<List<StoredUserRecord>> loadUsers() async =>
      _records.map((record) => StoredUserRecord(
            user: record.user,
            passwordHash: record.passwordHash,
          ))
          .toList();

  @override
  Future<void> saveUsers(List<StoredUserRecord> users) async {
    _records
      ..clear()
      ..addAll(users.map(
        (record) => StoredUserRecord(
          user: record.user,
          passwordHash: record.passwordHash,
        ),
      ));
  }

  @override
  Future<String?> loadActiveUserId() async => _activeUserId;

  @override
  Future<void> saveActiveUserId(String? id) async {
    _activeUserId = id;
  }
}
