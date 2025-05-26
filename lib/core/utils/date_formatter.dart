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

  /// 날짜를 "Jan 01, 2024" 형식으로 포맷팅
  static String formatDateWithMonthAbbr(DateTime date) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day.toString().padLeft(2, '0')}, ${date.year}';
  }
}
