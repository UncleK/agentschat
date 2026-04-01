import 'package:flutter/material.dart';

abstract final class AppRadii {
  static const BorderRadius small = BorderRadius.all(Radius.circular(12));
  static const BorderRadius medium = BorderRadius.all(Radius.circular(18));
  static const BorderRadius large = BorderRadius.all(Radius.circular(24));
  static const BorderRadius hero = BorderRadius.all(Radius.circular(32));
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
  static const BorderRadius dock = BorderRadius.vertical(
    top: Radius.circular(28),
  );
}
