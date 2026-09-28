import 'package:flutter/material.dart';

import '../core/store.dart';
import '../core/format.dart';
import 'dashboard.dart';

class ProfileScreen extends StatefulWidget {
  final ClubStore store;
  final Map<String, dynamic> member;
  const ProfileScreen({super.key, required this.store, required this.member});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? data;
  String? error;
  bool loading = true;
  bool visits = true;
  DateTimeRange? range;
  int loadId = 0;
  @override
  void initState() {
    super.initState();
    load();
    widget.store.addListener(sessionChanged);
  }

  void sessionChanged() {
    if (widget.store.session == null && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(sessionChanged);
    super.dispose();
  }

  Future<void> load() async {
    final requestId = ++loadId;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.store.profile(
        widget.member['memberId'],
        from: range?.start.toIso8601String().substring(0, 10),
        to: range?.end.toIso8601String().substring(0, 10),
      );
      if (mounted && requestId == loadId) setState(() => data = result);
    } catch (e) {
      if (mounted && requestId == loadId) setState(() => error = e.toString());
    } finally {
      if (mounted && requestId == loadId) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = (data?['member'] as Map?) ?? widget.member;
    final rows = (data?[visits ? 'visits' : 'events'] as List?) ?? [];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Member profile'),
        actions: [
          IconButton(
            tooltip: 'Refresh profile',
            onPressed: loading ? null : load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            Center(
              child: CircleAvatar(
                radius: 36,
                backgroundColor: const Color(0xffe8eee5),
                child: Text(
                  (m['name'] as String).characters.first,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: Color(0xff173f35),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              m['name'],
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              '${m['branch']} · ${m['regNo']}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Center(
              child: Chip(
                avatar: Icon(
                  m['presence'] == 'inside'
                      ? Icons.circle
                      : Icons.circle_outlined,
                  size: 12,
                ),
                label: Text(
                  m['presence'] == 'inside'
                      ? 'Recorded inside'
                      : m['presence'] == 'outside'
                      ? 'Recorded outside'
                      : 'Presence needs review',
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: stat('${m['visitCount']}', 'Visits started')),
                const SizedBox(width: 10),
                Expanded(
                  child: stat(
                    minutesLabel(m['completedMinutes'] as num),
                    'Confirmed time',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'All-time totals. Completed time is approximate and excludes uncertain visits.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            if ((m['flags'] as List).isNotEmpty)
              notice(
                'Attendance notes',
                (m['flags'] as List)
                    .map((f) => flagLabel(f.toString()))
                    .join(' · '),
                Icons.info_outline,
              ),
            if (data?['cached'] == true || data?['meta']?['stale'] == true)
              notice(
                'Last known profile',
                'This profile may be out of date. Last read ${clubTime(data?['meta']?['sourceReadAt'], date: true)} IST.',
                Icons.cloud_off_outlined,
              ),
            const SizedBox(height: 28),
            Row(
              children: [
                const Text(
                  'CLUB ACTIVITY',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: pickRange,
                  icon: const Icon(Icons.date_range, size: 16),
                  label: Text(range == null ? 'All dates' : 'Date filter'),
                ),
              ],
            ),
            if (range != null)
              Align(
                alignment: Alignment.centerLeft,
                child: InputChip(
                  label: Text(
                    '${range!.start.toIso8601String().substring(0, 10)} – ${range!.end.toIso8601String().substring(0, 10)}',
                  ),
                  onDeleted: () {
                    setState(() {
                      range = null;
                      data = null;
                    });
                    load();
                  },
                ),
              ),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Visits')),
                ButtonSegment(value: false, label: Text('Raw scans')),
              ],
              selected: {visits},
              onSelectionChanged: (v) => setState(() => visits = v.first),
            ),
            const SizedBox(height: 16),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (error != null)
              Column(
                children: [
                  notice('Could not refresh', error!, Icons.error_outline),
                  TextButton(onPressed: load, child: const Text('Retry')),
                ],
              ),
            if (!loading && rows.isEmpty && error == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No activity in this date range.',
                  textAlign: TextAlign.center,
                ),
              ),
            ...rows.map(
              (dynamic r) => visits
                  ? visitTile(Map<String, dynamic>.from(r))
                  : eventTile(Map<String, dynamic>.from(r)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> pickRange() async {
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: range,
    );
    if (result != null) {
      setState(() {
        range = result;
        data = null;
      });
      load();
    }
  }

  Widget stat(String value, String label) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    ),
  );
  Widget visitTile(Map<String, dynamic> r) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.schedule, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  clubTime(r['checkInAt'], date: true),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            r['checkOutAt'] == null
                ? 'Open visit · no checkout recorded'
                : 'Checked out ${clubTime(r['checkOutAt'], date: true)}',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(
            r['confirmedDurationMinutes'] == null
                ? (r['checkOutAt'] == null
                      ? 'Elapsed: ${minutesLabel((DateTime.now().difference(DateTime.parse(r['checkInAt'])).inMinutes).clamp(0, 10000000))} · ongoing'
                      : 'Duration uncertain')
                : minutesLabel(r['confirmedDurationMinutes'] as num),
            style: const TextStyle(
              color: Color(0xff287450),
              fontWeight: FontWeight.w700,
            ),
          ),
          if ((r['flags'] as List).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                (r['flags'] as List)
                    .map((f) => flagLabel(f.toString()))
                    .join(' · '),
                style: const TextStyle(fontSize: 11, color: Color(0xff775a2f)),
              ),
            ),
        ],
      ),
    ),
  );
  Widget eventTile(Map<String, dynamic> r) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      leading: Icon(r['action'] == 'CHECK-IN' ? Icons.login : Icons.logout),
      title: Text(
        r['action'] == 'CHECK-IN' ? 'Check-in' : 'Check-out',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${clubTime(r['occurredAt'], date: true)} IST${(r['flags'] as List).isNotEmpty ? '\n${(r['flags'] as List).map((f) => flagLabel(f.toString())).join(' · ')}' : ''}',
      ),
    ),
  );
}
