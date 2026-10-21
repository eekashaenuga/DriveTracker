import 'package:flutter/material.dart';

import '../../app/theme/dt_motion.dart';

Future<T?> showDTBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    sheetAnimationStyle: DTMotion.reduceMotionOf(context)
        ? AnimationStyle.noAnimation
        : null,
    builder: (context) => SafeArea(top: false, child: builder(context)),
  );
}
