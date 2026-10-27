import 'package:flutter/material.dart';

/// Navigasi standar PawFinder: transisi geser 300 ms (swipe-back pada iOS/Android).
Future<T?> pushPage<T>(BuildContext context, Widget page) => Navigator.of(context).push<T>(MaterialPageRoute<T>(builder: (_) => page));

void backToRoot(BuildContext context) => Navigator.of(context).popUntil((r) => r.isFirst);
