import 'package:flutter/material.dart';

class RtlHelper {
  // Matches Persian, Arabic, and extended Arabic Unicode blocks
  static final RegExp _persianArabicRegex = RegExp(
    r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]',
  );

  static bool isRtl(String text) {
    return _persianArabicRegex.hasMatch(text);
  }

  static TextDirection directionOf(String text) {
    return isRtl(text) ? TextDirection.rtl : TextDirection.ltr;
  }

  static TextAlign alignOf(String text) {
    return isRtl(text) ? TextAlign.right : TextAlign.left;
  }
}
