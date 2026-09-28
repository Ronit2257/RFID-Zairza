import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api.dart';

class ClubStore extends ChangeNotifier with WidgetsBindingObserver {
  final FlutterSecureStorage storage;
  AttendanceApi? api;
  Map<String, dynamic>? session;
  Map<String, dynamic>? snapshot;
  final Map<String, Map<String, dynamic>> profiles = {};
  bool booting = true, busy = false, offline = false;
  String? error;
  Timer? timer;
  int generation = 0;
  Future<void> _storageQueue = Future<void>.value();
  Future<void> _save(String key, String value, int epoch) {
    _storageQueue = _storageQueue.catchError((Object _) {}).then((_) async {
      if (epoch == generation) {
        await storage.write(key: key, value: value);
      }
    });
    return _storageQueue;
  }

  Future<void> _clearStorage() {
    _storageQueue = _storageQueue.catchError((Object _) {}).then((_) async {
      for (final key in ['connection', 'attendance', 'profiles']) {
        await storage.delete(key: key);
      }
    });
    return _storageQueue;
  }

  ClubStore({this.storage = const FlutterSecureStorage()});
  List<Map<String, dynamic>> get members =>
      ((snapshot?['data'] as List?) ?? []).cast<Map<String, dynamic>>();
  Map<String, dynamic> get meta =>
      (snapshot?['meta'] as Map<String, dynamic>?) ?? {};
  bool get stale =>
      offline ||
      meta['stale'] == true ||
      DateTime.now()
              .difference(
                DateTime.tryParse(meta['sourceReadAt'] ?? '') ?? DateTime(2000),
              )
              .inSeconds >
          90;
  bool get demo => session?['mode'] == 'demo';

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    try {
      final saved = await storage.read(key: 'connection');
      if (saved != null) {
        final c = jsonDecode(saved) as Map<String, dynamic>;
        api = AttendanceApi(AttendanceApi.validateUrl(c['url']), c['code']);
        session = Map<String, dynamic>.from(c['session']);
        final cached = await storage.read(key: 'attendance');
        if (cached != null) {
          snapshot = jsonDecode(cached) as Map<String, dynamic>;
        }
        final savedProfiles = await storage.read(key: 'profiles');
        if (savedProfiles != null) {
          final data = jsonDecode(savedProfiles) as Map<String, dynamic>;
          for (final entry in data.entries) {
            profiles[entry.key] = Map<String, dynamic>.from(entry.value);
          }
        }
        offline = true;
        await refresh();
        _startTimer();
      }
    } catch (_) {
      await logout();
    }
    booting = false;
    notifyListeners();
  }

  Future<void> login(String url, String code) async {
    busy = true;
    error = null;
    notifyListeners();
    AttendanceApi? candidate;
    try {
      final clean = AttendanceApi.validateUrl(url);
      candidate = AttendanceApi(clean, code.trim());
      final reply = await candidate.get('/v1/session');
      generation++;
      await _clearStorage();
      api?.close();
      api = candidate;
      session = Map<String, dynamic>.from(reply['data']);
      snapshot = null;
      profiles.clear();
      offline = false;
      await _save(
        'connection',
        jsonEncode({'url': clean, 'code': code.trim(), 'session': session}),
        generation,
      );
    } catch (e) {
      candidate?.close();
      error = e.toString();
    }
    busy = false;
    notifyListeners();
    if (session != null) {
      await refresh();
      _startTimer();
    }
  }

  void _startTimer() {
    timer?.cancel();
    if (session == null) return;
    timer = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && session != null) {
      refresh();
      _startTimer();
    } else {
      timer?.cancel();
    }
  }

  Future<void> refresh() async {
    if (api == null || busy) return;
    final epoch = generation;
    final activeApi = api!;
    busy = true;
    notifyListeners();
    try {
      final identity = await activeApi.get('/v1/session');
      Map<String, dynamic> data;
      try {
        data = await activeApi.all('/v1/members');
      } on ApiException catch (e) {
        if (e.status != 409) rethrow;
        data = await activeApi.all('/v1/members');
      }
      if (epoch != generation) return;
      session = Map<String, dynamic>.from(identity['data']);
      snapshot = data;
      offline = false;
      error = null;
      await _save('attendance', jsonEncode(data), epoch);
    } catch (e) {
      if (epoch != generation) return;
      if (e is ApiException && (e.status == 401 || e.status == 403)) {
        await logout();
        error = 'Your access has expired or been revoked. Contact the club operator.';
        notifyListeners();
      } else {
        offline = true;
        error = e.toString();
      }
    } finally {
      if (epoch == generation) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<Map<String, dynamic>> profile(
    String id, {
    String? from,
    String? to,
  }) async {
    final epoch = generation;
    final activeApi = api;
    if (activeApi == null) throw ApiException(401, 'Sign in again.');
    final key = '$id:${from ?? ''}:${to ?? ''}';
    try {
      final member = await activeApi.get('/v1/members/$id');
      final snapshotId = member['meta']['snapshotId'] as String;
      final query = {'snapshot': snapshotId, 'from': ?from, 'to': ?to};
      final events = await activeApi.all(
        '/v1/members/$id/events',
        query: query,
      );
      final visits = await activeApi.all(
        '/v1/members/$id/visits',
        query: query,
      );
      final result = {
        'member': member['data'],
        'events': events['data'],
        'visits': visits['data'],
        'meta': member['meta'],
        'cached': false,
      };
      if (epoch != generation) throw ApiException(401, 'Session changed.');
      profiles[key] = result;
      // Keep a bounded cache of the most recently viewed profiles.
      while (profiles.length > 20) {
        profiles.remove(profiles.keys.first);
      }
      await _save('profiles', jsonEncode(profiles), epoch);
      return result;
    } catch (e) {
      if (epoch != generation) rethrow;
      if (e is ApiException && (e.status == 401 || e.status == 403)) {
        await logout();
        rethrow;
      }
      if (profiles.containsKey(key)) return {...profiles[key]!, 'cached': true};
      rethrow;
    }
  }

  Future<void> logout() async {
    generation++;
    timer?.cancel();
    api?.close();
    api = null;
    session = null;
    snapshot = null;
    profiles.clear();
    busy = false;
    offline = false;
    error = null;
    await _clearStorage();
    notifyListeners();
  }

  @override
  void dispose() {
    timer?.cancel();
    api?.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
