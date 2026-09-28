import 'package:intl/intl.dart';

String clubTime(dynamic value, {bool date = false}) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  if (parsed == null) return 'No scans yet';
  return DateFormat(date ? 'd MMM y · h:mm a' : 'h:mm a')
      .format(parsed.toUtc().add(const Duration(hours: 5, minutes: 30)));
}

String minutesLabel(num minutes) {
  final rounded = minutes.round();
  return rounded < 60 ? '$rounded min' : '${rounded ~/ 60}h ${rounded % 60}m';
}

String flagLabel(String flag) => flag.split('_').join(' ');
