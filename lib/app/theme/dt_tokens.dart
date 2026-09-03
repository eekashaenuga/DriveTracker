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

  static const double card = 8;
  static const double control = 12;
  static const double sheet = 24;

  static BorderRadius get cardRadius => BorderRadius.circular(card);
  static BorderRadius get controlRadius => BorderRadius.circular(control);
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
