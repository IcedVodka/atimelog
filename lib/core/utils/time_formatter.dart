import 'package:intl/intl.dart';

String formatDurationText(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  final seconds = duration.inSeconds % 60;
  final buffer = StringBuffer();
  if (hours > 0) {
    buffer.write(hours.toString().padLeft(2, '0'));
    buffer.write(':');
  }
  buffer.write(minutes.toString().padLeft(2, '0'));
  buffer.write(':');
  buffer.write(seconds.toString().padLeft(2, '0'));
  return buffer.toString();
}

String formatLastActiveText(DateTime time) {
  final now = DateTime.now();
  final diff = now.difference(time);
  if (diff.inMinutes < 1) {
    return '刚刚';
  }
  if (diff.inHours < 1) {
    return '${diff.inMinutes} 分钟前';
  }
  if (diff.inDays < 1) {
    return '${diff.inHours} 小时前';
  }
  return DateFormat('MM-dd HH:mm').format(time);
}

String formatClock(DateTime dateTime) {
  return DateFormat('HH:mm').format(dateTime);
}
