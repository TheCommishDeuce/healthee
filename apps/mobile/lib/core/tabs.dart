/// The tab registry — ONE list, read by the bar and by the router's branches.
///
/// ## Why this is not a constant inside the bar widget
///
/// A `StatefulShellRoute.indexedStack` has an ordered list of branches and the
/// bar has an ordered list of items, and the two are joined by **index**:
/// `navigationShell.goBranch(i)` means "the i-th branch", not "the route named
/// on the i-th tab". Two lists in two files joined by an integer is a defect
/// waiting for somebody to insert a tab — the bar would light one screen and open
/// another, and nothing would fail to compile. So there is one list, and the
/// router builds its branches by iterating it.
///
/// That is also why [AppTab.screen] is here rather than a `switch` in the router:
/// a switch over routes needs an unreachable default, and an unreachable default
/// is a runtime error where a missing field would have been a compile error.
///
/// ## Four tabs — legacy's five, minus Actions
///
/// `~/projects/healthee-legacy/app/lib/ui/nav.dart` lists **Today · Sleep ·
/// Activity · Insights · Actions**. The personal-use rebuild removed Actions
/// with its challenge, program and recommendation screens (DESIGN_DECISIONS
/// P5), and the interactive coach that was once a button on Today (P3). The
/// nightly recommendation and correlation jobs still run on the server; their
/// findings stay readable on **Insights**, which is where a correlation belongs
/// — it is evidence read back from the owner's own history.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/router.dart';
import 'package:healthee/features/activity/activity_screen.dart';
import 'package:healthee/features/insights/insights_screen.dart';
import 'package:healthee/features/sleep/sleep_screen.dart';
import 'package:healthee/features/today/today_screen.dart';
import 'package:solar_icons/solar_icons.dart';

/// One tab: what it is called, its icon, its route, and the screen behind it.
@immutable
class AppTab {
  /// A tab in the bar. Every field is required — see the library docstring on
  /// why a tab with no destination is not a thing this list can express.
  const AppTab({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.route,
    required this.screen,
  });

  /// The name under the icon.
  final String label;

  /// The icon above it.
  final IconData icon;

  /// The same icon FILLED, for the tab you are on.
  ///
  /// Colour alone carried the selected state, and at 20px on a dim bar an
  /// accent outline and a grey outline are the same shape at two brightnesses.
  /// Weight is the second channel: the tab you are standing on is solid.
  final IconData activeIcon;

  /// The branch's root path. Deep links and `context.go` use it; the bar does
  /// not — it moves by branch index.
  final String route;

  /// Builds the tab's screen. The router calls it once per branch.
  final Widget Function() screen;
}

/// The tabs, in bar order — which is also branch order. See the docstring.
const List<AppTab> kAppTabs = <AppTab>[
  AppTab(
    label: 'Today',
    icon: SolarIconsOutline.sun,
    activeIcon: SolarIconsBold.sun,
    route: Routes.today,
    screen: TodayScreen.new,
  ),
  AppTab(
    label: 'Sleep',
    icon: SolarIconsOutline.moon,
    activeIcon: SolarIconsBold.moon,
    route: Routes.sleep,
    screen: SleepScreen.new,
  ),
  AppTab(
    label: 'Activity',
    icon: SolarIconsOutline.running,
    activeIcon: SolarIconsBold.running,
    route: Routes.activity,
    screen: ActivityScreen.new,
  ),
  AppTab(
    label: 'Insights',
    icon: SolarIconsOutline.chartSquare,
    activeIcon: SolarIconsBold.chartSquare,
    route: Routes.insights,
    screen: InsightsScreen.new,
  ),
];

/// Today's branch index — the one the back button falls home to.
///
/// A named constant rather than a literal `0` at the call sites that need it:
/// `shared/app_shell.dart`'s back rule and the router's initial location both
/// mean *the home tab*, and a reordering of [kAppTabs]
/// should move all three together or none.
const int kHomeTabIndex = 0;
