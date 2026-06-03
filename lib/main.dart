import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'db/database_helper.dart';
import 'screens/home_screen.dart';
import 'screens/products_screen.dart';
import 'screens/bills_screen.dart';
import 'screens/store_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/welcome_screen.dart';
import 'services/cloud_service.dart';
import 'theme/app_theme.dart';

export 'theme/app_colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
    return MaterialApp(
      title: 'Storely',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: AppColors.bg,
        textTheme: AppText.textTheme,
        colorScheme: const ColorScheme(
          brightness: Brightness.light,
          primary: AppColors.navy,
          onPrimary: Colors.white,
          primaryContainer: AppColors.navyLight,
          onPrimaryContainer: Colors.white,
          secondary: AppColors.amber,
          onSecondary: AppColors.navy,
          secondaryContainer: Color(0xFFFFF3D6),
          onSecondaryContainer: Color(0xFF6B4D00),
          tertiary: Color(0xFF0D9488),
          onTertiary: Colors.white,
          tertiaryContainer: Color(0xFFCCFBF1),
          onTertiaryContainer: Color(0xFF0D5549),
          error: AppColors.error,
          onError: Colors.white,
          surface: AppColors.surface,
          onSurface: AppColors.ink,
          onSurfaceVariant: AppColors.inkMuted,
          outline: AppColors.borderStrong,
          outlineVariant: AppColors.border,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          backgroundColor: AppColors.navy,
          foregroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleTextStyle: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: Colors.white,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.mdRadius,
            side: const BorderSide(color: AppColors.border),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          border: OutlineInputBorder(
            borderRadius: AppRadius.mdRadius,
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: AppRadius.mdRadius,
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: AppRadius.mdRadius,
            borderSide: const BorderSide(color: AppColors.navy, width: 1.5),
          ),
          hintStyle: const TextStyle(color: AppColors.inkFaint, fontSize: 14),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.navy,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.navy,
            side: const BorderSide(color: AppColors.borderStrong),
            shape: RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.amber,
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.navy,
          foregroundColor: Colors.white,
          elevation: 4,
        ),
        dividerTheme: const DividerThemeData(
          color: AppColors.border,
          thickness: 1,
          space: 1,
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.smRadius),
          side: BorderSide.none,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.navy,
          contentTextStyle: const TextStyle(color: Colors.white),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
        ),
        dialogTheme: DialogThemeData(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.lgRadius),
          backgroundColor: AppColors.surface,
          titleTextStyle: AppText.title,
        ),
      ),
      home: const AppGate(),
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
    if (_isLoading) return const Scaffold(backgroundColor: AppColors.bg);
    return _isFirstLaunch
        ? WelcomeScreen(onComplete: _completeWelcome)
        : const AppShell();
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: AppShadows.navBar,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                icon: Icons.home_outlined,
                activeIcon: Icons.home,
                label: 'Home',
                isActive: currentIndex == 0,
                onTap: () => onTabTap(0),
              ),
              _NavItem(
                icon: Icons.inventory_2_outlined,
                activeIcon: Icons.inventory_2,
                label: 'Products',
                isActive: currentIndex == 1,
                onTap: () => onTabTap(1),
              ),
              GestureDetector(
                onTap: onScanTap,
                child: Container(
                  width: 56,
                  height: 56,
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
                    size: 28,
                  ),
                ),
              ),
              _NavItem(
                icon: Icons.receipt_long_outlined,
                activeIcon: Icons.receipt_long,
                label: 'Bills',
                isActive: currentIndex == 2,
                onTap: () => onTabTap(2),
              ),
              _NavItem(
                icon: Icons.storefront_outlined,
                activeIcon: Icons.storefront,
                label: 'Store',
                isActive: currentIndex == 3,
                onTap: () => onTabTap(3),
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
              color: isActive ? AppColors.navy : AppColors.inkMuted,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? AppColors.navy : AppColors.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
