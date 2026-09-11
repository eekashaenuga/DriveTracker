import 'package:flutter/material.dart';

class DTSpacing {
  const DTSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 40;
}

class DTRadii {
  const DTRadii._();

  static const double xs = 6;
  static const double card = 8;
  static const double control = 12;
  static const double hero = 20;
  static const double sheet = 24;

  static BorderRadius get smallRadius => BorderRadius.circular(xs);
  static BorderRadius get cardRadius => BorderRadius.circular(card);
  static BorderRadius get controlRadius => BorderRadius.circular(control);
  static BorderRadius get heroRadius => BorderRadius.circular(hero);
}

class DTIconSizes {
  const DTIconSizes._();

  static const double sm = 18;
  static const double md = 22;
  static const double lg = 30;
}

class DTDurations {
  const DTDurations._();

  static const Duration fast = Duration(milliseconds: 160);
  static const Duration normal = Duration(milliseconds: 240);
}

class DTAccents {
  const DTAccents._();

  static Color fuel(BuildContext context) {
    return _tone(context, const Color(0xFF0F766E), const Color(0xFF5EEAD4));
  }

  static Color service(BuildContext context) {
    return _tone(context, const Color(0xFFB45309), const Color(0xFFFBBF24));
  }

  static Color expense(BuildContext context) {
    return _tone(context, const Color(0xFFB91C1C), const Color(0xFFFCA5A5));
  }

  static Color income(BuildContext context) {
    return _tone(context, const Color(0xFF15803D), const Color(0xFF86EFAC));
  }

  static Color odometer(BuildContext context) {
    return _tone(context, const Color(0xFF2563EB), const Color(0xFF93C5FD));
  }

  static Color maintenance(BuildContext context) {
    return _tone(context, const Color(0xFFD97706), const Color(0xFFFCD34D));
  }

  static Color documents(BuildContext context) {
    return _tone(context, const Color(0xFF6D28D9), const Color(0xFFC4B5FD));
  }

  static Color storage(BuildContext context) {
    return _tone(context, const Color(0xFF475569), const Color(0xFFCBD5E1));
  }

  static Color neutral(BuildContext context) {
    return Theme.of(context).colorScheme.primary;
  }

  static Color warning(BuildContext context) {
    return Theme.of(context).colorScheme.tertiary;
  }

  static Color danger(BuildContext context) {
    return Theme.of(context).colorScheme.error;
  }

  static Color _tone(BuildContext context, Color light, Color dark) {
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }
}
