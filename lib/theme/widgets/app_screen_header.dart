import 'package:flutter/material.dart';
import '../app_colors.dart';

/// Unified compact navy screen header, usable as:
/// 1. A SliverPersistentHeader delegate (for scroll-collapsing headers)
/// 2. A plain AppBar-style widget for simple screens
///
/// All main screens (Home, Products, Bills, Store) use this.
class AppScreenHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String title;
  final String? subtitle;
  final double topPadding;
  final List<Widget>? actions;

  /// When provided, replaces the title/subtitle area — e.g. an inline,
  /// borderless search field shown after tapping the header search icon.
  final Widget? titleOverride;

  const AppScreenHeaderDelegate({
    required this.title,
    this.subtitle,
    required this.topPadding,
    this.actions,
    this.titleOverride,
  });

  @override
  double get minExtent => topPadding + 40;

  @override
  double get maxExtent => topPadding + (subtitle != null ? 64 : 48);

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final range = maxExtent - minExtent;
    final collapsed = range == 0 ? 1.0 : (shrinkOffset / range).clamp(0.0, 1.0);
    final expanded = 1.0 - collapsed;

    return Container(
      color: AppColors.darkBg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: titleOverride ??
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTitle(
                          fontSize: _lerp(20, 16, collapsed),
                        ),
                        if (subtitle != null)
                          Opacity(
                            opacity: expanded,
                            child: Text(
                              subtitle!,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
              ),
              if (actions != null) ...actions!,
            ],
          ),
        ),
      ),
    );
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  Widget _buildTitle({required double fontSize}) {
    final base = TextStyle(
      color: Colors.white,
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      height: 1.15,
    );
    // Brand: render trailing "ly" of "Storely" in amber.
    if (title == 'Storely') {
      return Text.rich(
        TextSpan(
          style: base,
          children: const [
            TextSpan(text: 'Store'),
            TextSpan(text: 'ly', style: TextStyle(color: AppColors.amber)),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return Text(
      title,
      style: base,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  @override
  bool shouldRebuild(covariant AppScreenHeaderDelegate old) =>
      old.title != title ||
      old.subtitle != subtitle ||
      old.topPadding != topPadding ||
      old.titleOverride != titleOverride;
}

/// Simple navy AppBar for secondary/modal screens (not collapsing).
PreferredSizeWidget navyAppBar({
  required String title,
  List<Widget>? actions,
  bool showBack = true,
}) {
  return AppBar(
    title: Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
    ),
    elevation: 0,
    scrolledUnderElevation: 0,
    automaticallyImplyLeading: showBack,
    actions: actions,
  );
}
