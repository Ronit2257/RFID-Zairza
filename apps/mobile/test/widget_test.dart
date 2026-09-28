import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zairza_attendance/core/api.dart';
import 'package:zairza_attendance/core/store.dart';
import 'package:zairza_attendance/screens/dashboard.dart';
import 'package:zairza_attendance/screens/login.dart';

void main() {
  test('API rejects unsafe endpoints and handles revoked access', () async {
    expect(
      () => AttendanceApi.validateUrl('http://example.com'),
      throwsA(isA<ApiException>()),
    );
    expect(
      () => AttendanceApi.validateUrl('https://user:pass@example.com'),
      throwsA(isA<ApiException>()),
    );
    final api = AttendanceApi(
      'https://example.com',
      'secret',
      client: MockClient((req) async {
        expect(req.headers['Authorization'], 'Bearer secret');
        return http.Response(
          jsonEncode({
            'error': {'message': 'Revoked'},
          }),
          401,
        );
      }),
    );
    await expectLater(
      api.get('/v1/members'),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)),
    );
    api.close();
  });
  test('API loads successive pages preserving filters', () async {
    var calls = 0;
    final api = AttendanceApi(
      'https://example.com',
      'secret',
      client: MockClient((req) async {
        calls++;
        expect(req.url.queryParameters['from'], '2026-09-01');
        if (calls == 1) {
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 'a'},
              ],
              'meta': {},
              'nextCursor': 'next',
            }),
            200,
          );
        }
        expect(req.url.queryParameters['cursor'], 'next');
        return http.Response(
          jsonEncode({
            'data': [
              {'id': 'b'},
            ],
            'nextCursor': null,
          }),
          200,
        );
      }),
    );
    final result = await api.all('/v1/events', query: {'from': '2026-09-01'});
    expect((result['data'] as List).length, 2);
    api.close();
  });
  testWidgets('leadership login has URL/code fields and no public signup', (
    tester,
  ) async {
    final store = ClubStore();
    await tester.pumpWidget(MaterialApp(home: LoginScreen(store: store)));
    expect(find.text('Enter the club'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Sign up'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
  testWidgets('empty source and failed source are different states', (
    tester,
  ) async {
    final store = ClubStore();
    store.session = {'name': 'Operator', 'mode': 'live'};
    store.snapshot = {
      'data': [],
      'meta': {'sourceReadAt': DateTime.now().toIso8601String(), 'quality': {}},
    };
    await tester.pumpWidget(MaterialApp(home: Dashboard(store: store)));
    expect(find.text('The club is quiet right now.'), findsOneWidget);
    store.snapshot = null;
    store.error = 'Source unavailable';
    await tester.pumpWidget(
      MaterialApp(
        home: Dashboard(key: UniqueKey(), store: store),
      ),
    );
    expect(find.text('Attendance unavailable'), findsOneWidget);
    expect(find.text('The club is quiet right now.'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
