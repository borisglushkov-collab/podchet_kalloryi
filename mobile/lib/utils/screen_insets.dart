import 'package:flutter/material.dart';

/// Отступы под системные панели (статус-бар / Назад·Домой·Недавние).
abstract final class ScreenInsets {
  static double top(BuildContext context) =>
      MediaQuery.viewPaddingOf(context).top;

  static double bottom(BuildContext context) =>
      MediaQuery.viewPaddingOf(context).bottom;

  /// Нижний padding для скролла на вкладке внутри MainShell
  /// (над нижней навигацией; системный inset уже в навбаре).
  static EdgeInsets tabScroll(BuildContext context, {double bottom = 24}) =>
      EdgeInsets.fromLTRB(16, 0, 16, bottom);

  /// Нижний padding для полноценного экрана (без shell-навбара).
  static EdgeInsets routeScroll(
    BuildContext context, {
    double horizontal = 16,
    double top = 16,
    double bottom = 16,
  }) {
    return EdgeInsets.fromLTRB(
      horizontal,
      top,
      horizontal,
      bottom + MediaQuery.viewPaddingOf(context).bottom,
    );
  }
}
