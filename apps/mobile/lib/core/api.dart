import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => message;
}

class AttendanceApi {
  final String baseUrl;
  final String code;
  final http.Client client;
  AttendanceApi(this.baseUrl, this.code, {http.Client? client})
    : client = client ?? http.Client();

  static String validateUrl(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !['https', 'http'].contains(uri.scheme)) {
      throw ApiException(400, 'Enter a valid server URL.');
    }
    if (uri.scheme != 'https' &&
        !(kDebugMode &&
            ['127.0.0.1', 'localhost', '10.0.2.2'].contains(uri.host))) {
      throw ApiException(400, 'Use HTTPS for your club server.');
    }
    return input.trim().replaceFirst(RegExp(r'/+$'), '');
  }

  Future<Map<String, dynamic>> get(
    String path, [
    Map<String, String>? query,
  ]) async {
    try {
      final response = await client
          .get(
            Uri.parse('$baseUrl$path').replace(queryParameters: query),
            headers: {'Authorization': 'Bearer $code'},
          )
          .timeout(const Duration(seconds: 25));
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          (body['error'] as Map?)?['message'] as String? ??
              'Unable to load attendance.',
        );
      }
      return body;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(
        0,
        'Cannot reach the club server. Check your connection and retry.',
      );
    }
  }

  Future<Map<String, dynamic>> all(
    String path, {
    Map<String, String> query = const {},
  }) async {
    final first = await get(path, {...query, 'limit': '100'});
    final items = List<dynamic>.from(first['data'] as List);
    var cursor = first['nextCursor'] as String?;
    while (cursor != null) {
      final next = await get(path, {
        ...query,
        'limit': '100',
        'cursor': cursor,
      });
      items.addAll(next['data'] as List);
      cursor = next['nextCursor'] as String?;
    }
    return {...first, 'data': items};
  }

  void close() => client.close();
}
