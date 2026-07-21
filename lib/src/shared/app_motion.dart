import 'package:flutter/material.dart';

import '../core/cache/storage_models.dart';

Duration motionDuration(
  BuildContext context,
  MotionPreference preference, {
  int expressive = 520,
  int balanced = 280,
}) {
  if (MediaQuery.maybeOf(context)?.disableAnimations == true ||
      preference == MotionPreference.minimal) {
    return const Duration(milliseconds: 1);
  }
  return Duration(
    milliseconds: preference == MotionPreference.expressive
        ? expressive
        : balanced,
  );
}

Curve motionCurve(MotionPreference preference) =>
    preference == MotionPreference.expressive
    ? Curves.easeOutBack
    : Curves.easeOutCubic;
