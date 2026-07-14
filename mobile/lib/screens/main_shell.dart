import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../theme/app_theme.dart';
import 'add_food_screen.dart';
import 'analytics_screen.dart';
import 'diary_screen.dart';
import 'profile_screen.dart';
import 'suggestions_screen.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final dateStr = formatDate(ref.watch(selectedDateProvider));
    final profile = ref.watch(profileProvider).valueOrNull;

    final pages = <Widget>[
      const DiaryScreen(),
      const AnalyticsScreen(),
      const SizedBox.shrink(),
      SuggestionsScreen(date: dateStr, embedded: true),
      const ProfileScreen(embedded: true),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      extendBody: false,
      extendBodyBehindAppBar: false,
      // Edge-to-edge: вкладки не уходят под статус-бар и боковые вырезы.
      // Низ — в _WellnessNavBar (viewPadding.bottom).
      body: SafeArea(
        top: true,
        left: true,
        right: true,
        bottom: false,
        child: IndexedStack(
          index: _index == 2 ? 0 : _index,
          children: pages,
        ),
      ),
      bottomNavigationBar: _WellnessNavBar(
        selectedIndex: _index == 2 ? 0 : _index,
        onSelected: (i) {
          if (i == 2) {
            if (profile == null) {
              _openProfile();
              return;
            }
            _openAddFood(dateStr);
            return;
          }
          setState(() => _index = i);
        },
      ),
    );
  }

  Future<void> _openAddFood(String dateStr) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddFoodScreen(date: dateStr)),
    );
    ref.invalidate(dailyEntriesProvider(dateStr));
    ref.invalidate(dailyTotalsProvider(dateStr));
  }

  void _openProfile() {
    setState(() => _index = 4);
  }
}

class _WellnessNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _WellnessNavBar({
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    // Edge-to-edge Android: системные кнопки Назад/Домой поверх контента,
    // если не учесть viewPadding.bottom.
    final systemBottom = MediaQuery.viewPaddingOf(context).bottom;
    return Material(
      color: AppColors.surface,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: Colors.black.withValues(alpha: 0.06))),
        ),
        padding: EdgeInsets.fromLTRB(8, 8, 8, 8 + systemBottom),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _NavItem(
              label: 'Сегодня',
              icon: Icons.wb_sunny_outlined,
              selected: selectedIndex == 0,
              onTap: () => onSelected(0),
            ),
            _NavItem(
              label: 'Аналитика',
              icon: Icons.insights_outlined,
              selected: selectedIndex == 1,
              onTap: () => onSelected(1),
            ),
            _FabNavItem(onTap: () => onSelected(2)),
            _NavItem(
              label: 'Коуч',
              icon: Icons.psychology_outlined,
              selected: selectedIndex == 3,
              onTap: () => onSelected(3),
            ),
            _NavItem(
              label: 'Профиль',
              icon: Icons.person_outline,
              selected: selectedIndex == 4,
              onTap: () => onSelected(4),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _FabNavItem extends StatelessWidget {
  final VoidCallback onTap;

  const _FabNavItem({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        margin: const EdgeInsets.only(bottom: 4),
        decoration: const BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
    );
  }
}
