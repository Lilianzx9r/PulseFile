// lib/utils/top_snack.dart
import 'package:flutter/material.dart';

void showTopSnack(BuildContext context, String message,
    {Color? backgroundColor, Duration duration = const Duration(seconds: 3)}) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: backgroundColor,
      duration: duration,
      behavior: SnackBarBehavior.floating,
    ));
}
