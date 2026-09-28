import 'package:flutter/material.dart';

import '../core/store.dart';
import '../core/format.dart';
import 'profile.dart';

class Dashboard extends StatefulWidget {
  final ClubStore store;
  const Dashboard({super.key, required this.store});
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  int tab = 0;
  String query = '';
  String? branch;
  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final members = s.members
        .where(
          (m) =>
              (tab != 0 || m['presence'] == 'inside') &&
              (branch == null || m['branch'] == branch) &&
              '${m['name']} ${m['regNo']}'.toLowerCase().contains(
                query.toLowerCase(),
              ),
        )
        .toList();
    final branches =
        s.members
            .map((m) => m['branch'] as String)
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ZAIRZA',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
            fontSize: 18,
          ),
        ),
        actions: [
          if (s.demo)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Chip(label: Text('DEMO')),
            ),
          IconButton(
            tooltip: 'Refresh attendance',
            onPressed: s.busy ? null : s.refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: tab == 2
          ? settings(context, s)
          : RefreshIndicator(
              onRefresh: s.refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Text(
                    tab == 0 ? 'The club, right now.' : 'People make the club.',
                    style: const TextStyle(
                      fontSize: 29,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.7,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tab == 0
                        ? 'A familiar face is just a tap away.'
                        : 'Your members and their time at Zairza.',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 22),
                  if (tab == 0)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xff173f35),
                        borderRadius: BorderRadius.circular(26),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: s.stale
                                      ? Colors.amber
                                      : const Color(0xffbfe3a6),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                s.snapshot == null
                                    ? 'WAITING FOR DATA'
                                    : s.stale
                                    ? 'LAST KNOWN PRESENCE'
                                    : 'RECORDED INSIDE',
                                style: const TextStyle(
                                  color: Color(0xffd5e6dc),
                                  letterSpacing: 1.6,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                s.snapshot == null
                                    ? '—'
                                    : '${s.members.where((m) => m['presence'] == 'inside').length}',
                                style: const TextStyle(
                                  fontSize: 64,
                                  height: 1.1,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.only(left: 12, bottom: 10),
                                child: Text(
                                  'members',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            s.snapshot == null
                                ? 'Your attendance will appear here.'
                                : '${s.members.length} members in the directory · Updated ${clubTime(s.meta['sourceReadAt'])} IST',
                            style: const TextStyle(
                              color: Color(0xffd5e6dc),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (s.busy)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  if (s.stale && s.snapshot != null)
                    notice(
                      'Showing last known data',
                      s.error ?? 'The source has not refreshed recently. Pull down to retry.',
                      Icons.cloud_off_outlined,
                    ),
                  if (s.snapshot == null && s.error != null)
                    notice(
                      'Attendance unavailable',
                      s.error!,
                      Icons.wifi_off_rounded,
                    ),
                  if (s.demo)
                    notice(
                      'Sample data',
                      'This is a demonstration. These records are not live club presence.',
                      Icons.science_outlined,
                    ),
                  if ((s.meta['quality'] as Map?)?.values.any(
                        (v) => v is num && v > 0,
                      ) ==
                      true)
                    notice(
                      'Some records need context',
                      'Test records and invalid rows are excluded. Check Settings for source quality.',
                      Icons.info_outline,
                    ),
                  const SizedBox(height: 20),
                  TextField(
                    onChanged: (v) => setState(() => query = v),
                    decoration: const InputDecoration(
                      hintText: 'Search name or registration',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                  if (tab == 1 && branches.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ChoiceChip(
                              label: const Text('All branches'),
                              selected: branch == null,
                              onSelected: (_) => setState(() => branch = null),
                            ),
                            ...branches.map(
                              (b) => Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: ChoiceChip(
                                  label: Text(b),
                                  selected: branch == b,
                                  onSelected: (_) => setState(() => branch = b),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Text(
                        tab == 0 ? 'INSIDE NOW' : 'MEMBER DIRECTORY',
                        style: const TextStyle(
                          letterSpacing: 1.5,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${members.length}',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (members.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Column(
                        children: [
                          Icon(
                            tab == 0
                                ? Icons.chair_outlined
                                : Icons.people_outline,
                            size: 44,
                            color: Colors.grey.shade500,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            s.snapshot == null
                                ? 'Waiting for attendance'
                                : query.isNotEmpty || branch != null
                                ? 'No matching members'
                                : tab == 0
                                ? 'The club is quiet right now.'
                                : 'No members have scanned yet.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Pull down to refresh.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ...members.map(
                    (m) => MemberCard(
                      member: m,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ProfileScreen(store: s, member: m),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (v) => setState(() {
          tab = v;
          query = '';
          branch = null;
        }),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.door_front_door_outlined),
            selectedIcon: Icon(Icons.door_front_door),
            label: 'Inside now',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Members',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget settings(BuildContext context, ClubStore s) => ListView(
    padding: const EdgeInsets.all(22),
    children: [
      const Text(
        'Your club connection',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 22),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.session?['name'] ?? 'Leadership',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text('Leadership access'),
              const Divider(height: 30),
              Text(s.api?.baseUrl ?? ''),
              const SizedBox(height: 12),
              Text('Source: ${s.demo ? 'Sample records' : 'Google Sheets'}'),
              const SizedBox(height: 8),
              Text(
                'Last read: ${clubTime(s.meta['sourceReadAt'], date: true)} IST',
              ),
              const SizedBox(height: 8),
              Text(
                s.stale
                    ? 'Status: last known data'
                    : 'Status: source refreshed',
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      const Text(
        'SOURCE QUALITY',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
          fontSize: 11,
        ),
      ),
      const SizedBox(height: 8),
      ...((s.meta['quality'] as Map?) ?? {}).entries.map(
        (e) => ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(qualityLabel(e.key.toString())),
          trailing: Text('${e.value}'),
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        'Presence follows the last recorded scan. Missed scans or offline reader uploads can affect it. A fresh sheet read does not prove the reader is online.',
        style: TextStyle(color: Colors.grey, height: 1.5),
      ),
      const SizedBox(height: 26),
      OutlinedButton.icon(
        onPressed: () => s.logout(),
        icon: const Icon(Icons.logout),
        label: const Text('Sign out and clear saved attendance'),
      ),
    ],
  );
  String qualityLabel(String key) =>
      {
        'invalidRows': 'Invalid rows',
        'testExclusions': 'Test records excluded',
        'exactDuplicates': 'Duplicate rows',
        'conflictingIds': 'Conflicting event IDs',
        'identityConflicts': 'Card identity conflicts',
      }[key] ??
      key;
}

Widget notice(String title, String message, IconData icon) => Container(
  margin: const EdgeInsets.only(top: 14),
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: const Color(0xfff0e8d8),
    borderRadius: BorderRadius.circular(16),
  ),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 20, color: const Color(0xff775a2f)),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(message, style: const TextStyle(fontSize: 12, height: 1.5)),
          ],
        ),
      ),
    ],
  ),
);

class MemberCard extends StatelessWidget {
  final Map<String, dynamic> member;
  final VoidCallback onTap;
  const MemberCard({super.key, required this.member, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final name = member['name'] as String;
    final inside = member['presence'] == 'inside';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: const Color(0xffe8eee5),
          child: Text(
            name.isEmpty ? '?' : name.characters.first.toUpperCase(),
            style: const TextStyle(
              color: Color(0xff173f35),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            '${member['branch']} · ${member['regNo']}',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              inside
                  ? 'Inside'
                  : member['presence'] == 'unknown'
                  ? 'Review'
                  : 'Outside',
              style: TextStyle(
                color: inside ? const Color(0xff287450) : Colors.grey.shade600,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              clubTime(member['lastEventAt']),
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
