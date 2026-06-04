import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'db/database_helper.dart';
import 'screens/app_lock_gate.dart';
import 'screens/home_screen.dart';
import 'screens/products_screen.dart';
import 'screens/bills_screen.dart';
import 'screens/store_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/welcome_screen.dart';
import 'services/app_settings_service.dart';
import 'services/cloud_service.dart';
import 'services/home_section_prefs.dart';
import 'theme/app_theme.dart';
import 'utils/test_keys.dart';

export 'theme/app_colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettingsService.instance.load();
  await HomeSectionPrefs.instance.load();
  await CloudService.instance.initialize();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const StorelyApp());
}

class StorelyApp extends StatelessWidget {
  const StorelyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSettingsService.instance,
      builder: (context, _) => MaterialApp(
        title: 'Storely',
        debugShowCheckedModeBanner: false,
        theme: StorelyTheme.light(),
        darkTheme: StorelyTheme.dark(),
        themeMode: AppSettingsService.instance.themeMode,
        home: const AppGate(),
      ),
    );
  }
}

class AppGate extends StatefulWidget {
  const AppGate({super.key});

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  bool _isLoading = true;
  bool _isFirstLaunch = true;

  @override
  void initState() {
    super.initState();
    _checkFirstLaunch();
  }

  Future<void> _checkFirstLaunch() async {
    final profile = await DatabaseHelper.instance.getShopProfile();
    final name = profile?.name.trim();
    final needsSetup = name == null || name.isEmpty || name == 'My Shop';
    if (mounted) {
      setState(() {
        _isFirstLaunch = needsSetup;
        _isLoading = false;
      });
    }
  }

  Future<void> _completeWelcome() async {
    final profile = await DatabaseHelper.instance.getShopProfile();
    final name = profile?.name.trim();
    if (mounted) {
      setState(() {
        _isFirstLaunch = name == null || name.isEmpty || name == 'My Shop';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      );
    }
    return _isFirstLaunch
        ? WelcomeScreen(onComplete: _completeWelcome)
        : const AppLockGate(child: AppShell());
  }
}

// ── App Shell with Bottom Nav ── (DO NOT CHANGE)
class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;
  int _homeRefreshToken = 0;
  int _productsRefreshToken = 0;
  int _billsRefreshToken = 0;
  int _storeRefreshToken = 0;
  int _productPurchaseRequestToken = 0;

  void _switchTab(int index) {
    setState(() {
      _currentIndex = index;
      if (index == 0) _homeRefreshToken++;
      if (index == 1) _productsRefreshToken++;
      if (index == 2) _billsRefreshToken++;
      if (index == 3) _storeRefreshToken++;
    });
  }

  void _openScanner() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    ).then((_) {
      setState(() {
        _homeRefreshToken++;
        _productsRefreshToken++;
        _billsRefreshToken++;
      });
    });
  }

  void _goHomeFromBack() {
    if (_currentIndex == 0) return;
    _switchTab(0);
  }

  void _openProductPurchaseFlow() {
    setState(() {
      _productPurchaseRequestToken++;
    });
  }

  void _refreshAfterProductPurchaseFlow() {
    if (!mounted) return;
    setState(() {
      _homeRefreshToken++;
      _productsRefreshToken++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        refreshToken: _homeRefreshToken,
        onNavigate: _switchTab,
        onScan: _openScanner,
        onAddProduct: _openProductPurchaseFlow,
      ),
      ProductsScreen(
        refreshToken: _productsRefreshToken,
        isActiveMainTab: _currentIndex == 1,
        openPurchaseFlowToken: _productPurchaseRequestToken,
        onPurchaseFlowComplete: _refreshAfterProductPurchaseFlow,
        onBackToHome: _goHomeFromBack,
      ),
      BillsScreen(refreshToken: _billsRefreshToken),
      StoreScreen(refreshToken: _storeRefreshToken),
    ];

    return PopScope(
      canPop: _currentIndex == 0 || _currentIndex == 1,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _currentIndex == 1) return;
        _goHomeFromBack();
      },
      child: Scaffold(
        body: IndexedStack(index: _currentIndex, children: pages),
        bottomNavigationBar: _BottomNavBar(
          currentIndex: _currentIndex,
          onTabTap: _switchTab,
          onScanTap: _openScanner,
        ),
      ),
    );
  }
}

// ── Custom Bottom Nav Bar (DO NOT CHANGE) ──
class _BottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTabTap;
  final VoidCallback onScanTap;

  const _BottomNavBar({
    required this.currentIndex,
    required this.onTabTap,
    required this.onScanTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    final surface = AppColors.surfaceOf(context);
    final shadowColor = isDark ? Colors.black : AppColors.navy;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        border: Border(top: BorderSide(color: AppColors.borderOf(context))),
        boxShadow: [
          BoxShadow(
            color: shadowColor.withValues(alpha: isDark ? 0.5 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              TestKeys.tag(
                TestKeys.navHome,
                _NavItem(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home,
                  label: 'Home',
                  isActive: currentIndex == 0,
                  onTap: () => onTabTap(0),
                ),
                button: true,
              ),
              TestKeys.tag(
                TestKeys.navProducts,
                _NavItem(
                  icon: Icons.inventory_2_outlined,
                  activeIcon: Icons.inventory_2,
                  label: 'Products',
                  isActive: currentIndex == 1,
                  onTap: () => onTabTap(1),
                ),
                button: true,
              ),
              TestKeys.tag(
                TestKeys.navScan,
                GestureDetector(
                  onTap: onScanTap,
                  child: Container(
                    width: 48,
                    height: 48,
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(
                      color: AppColors.amber,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.amber.withValues(alpha: 0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.qr_code_scanner_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
                label: 'Scan',
                button: true,
              ),
              TestKeys.tag(
                TestKeys.navBills,
                _NavItem(
                  icon: Icons.receipt_long_outlined,
                  activeIcon: Icons.receipt_long,
                  label: 'Bills',
                  isActive: currentIndex == 2,
                  onTap: () => onTabTap(2),
                ),
                button: true,
              ),
              TestKeys.tag(
                TestKeys.navStore,
                _NavItem(
                  icon: Icons.storefront_outlined,
                  activeIcon: Icons.storefront,
                  label: 'Store',
                  isActive: currentIndex == 3,
                  onTap: () => onTabTap(3),
                ),
                button: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon, activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = AppColors.brandOf(context);
    final inactiveColor = AppColors.inkMutedOf(context);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 60,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              color: isActive ? activeColor : inactiveColor,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? activeColor : inactiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
