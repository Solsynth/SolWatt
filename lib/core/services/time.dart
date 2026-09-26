import 'package:easy_localization/easy_localization.dart';

/// Duration/date formatting used by the ported drive UI. Trimmed to the
/// helpers the drive actually calls (Solian's full extension set included
/// relative-time and offset helpers that pull extra runtime delegates).
extension DurationFormatter on Duration {
  String formatDuration() {
    final isNegative = inMicroseconds < 0;
    final positiveDuration = isNegative ? -this : this;

    final hours = positiveDuration.inHours.toString().padLeft(2, '0');
    final minutes = (positiveDuration.inMinutes % 60).toString().padLeft(
      2,
      '0',
    );
    final seconds = (positiveDuration.inSeconds % 60).toString().padLeft(
      2,
      '0',
    );

    return '${isNegative ? '-' : ''}$hours:$minutes:$seconds';
  }

  String formatShortDuration() {
    final isNegative = inMicroseconds < 0;
    final positiveDuration = isNegative ? -this : this;

    final hours = positiveDuration.inHours;
    final minutes = (positiveDuration.inMinutes % 60).toString().padLeft(
      2,
      '0',
    );
    final seconds = (positiveDuration.inSeconds % 60).toString().padLeft(
      2,
      '0',
    );
    final milliseconds = (positiveDuration.inMilliseconds % 1000)
        .toString()
        .padLeft(3, '0');

    String result;
    if (hours > 0) {
      result =
          '${isNegative ? '-' : ''}${hours.toString().padLeft(2, '0')}:$minutes:$seconds.$milliseconds';
    } else {
      result = '${isNegative ? '-' : ''}$minutes:$seconds.$milliseconds';
    }
    return result;
  }
}

extension DateTimeFormatter on DateTime {
  String formatSystem() {
    return DateFormat.yMd().add_jm().format(toLocal());
  }
}
