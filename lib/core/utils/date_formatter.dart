import 'package:intl/intl.dart';

class DateFormatter {
  static String formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      // 오늘
      return '오늘 ${DateFormat('HH:mm').format(date)}';
    } else if (difference.inDays == 1) {
      // 어제
      return '어제 ${DateFormat('HH:mm').format(date)}';
    } else if (difference.inDays < 7) {
      // 일주일 이내
      return '${difference.inDays}일 전';
    } else {
      // 일주일 이상
      return DateFormat('yyyy.MM.dd').format(date);
    }
  }

  static String formatDateTime(DateTime date) {
    return DateFormat('yyyy.MM.dd HH:mm').format(date);
  }
}
