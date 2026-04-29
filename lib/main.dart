import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/home_screen.dart';
import 'screens/products_screen.dart';
import 'screens/bills_screen.dart';
import 'screens/store_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/welcome_screen.dart';
import 'services/cloud_service.dart';

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

// ── App Colors ──
class AppColors {
  static const navy = Color(0xFF1B2838);
  static const navyLight = Color(0xFF243447);
  static const amber = Color(0xFFF5A623);
  static const cream = Color(0xFFF8F4ED);
  static const creamDark = Color(0xFFF0EBE3);
  static const textDark = Color(0xFF1B2838);
  static const textMuted = Color(0xFF7A8599);
  static const success = Color(0xFF22C55E);
  static const error = Color(0xFFEF4444);
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
        scaffoldBackgroundColor: AppColors.cream,
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
          surface: Colors.white,
          onSurface: AppColors.textDark,
          onSurfaceVariant: AppColors.textMuted,
          outline: Color(0xFFD1C9BC),
          outlineVariant: Color(0xFFE8E2D9),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          backgroundColor: AppColors.navy,
          foregroundColor: Colors.white,
          scrolledUnderElevation: 0,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.cream,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
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
    final prefs = await SharedPreferences.getInstance();
    final isFirst = prefs.getBool('is_first_launch') ?? true;
    if (mounted) {
      setState(() {
        _isFirstLaunch = isFirst;
        _isLoading = false;
      });
    }
  }

  Future<void> _completeWelcome() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_first_launch', false);
    if (mounted) {
      setState(() {
        _isFirstLaunch = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(backgroundColor: AppColors.cream);
    return _isFirstLaunch
        ? WelcomeScreen(onComplete: _completeWelcome)
        : const AppShell();
  }
}

// ── App Shell with Bottom Nav ──
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

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        refreshToken: _homeRefreshToken,
        onNavigate: _switchTab,
        onScan: _openScanner,
      ),
      ProductsScreen(refreshToken: _productsRefreshToken),
      BillsScreen(refreshToken: _billsRefreshToken),
      StoreScreen(refreshToken: _storeRefreshToken),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: pages),
      bottomNavigationBar: _BottomNavBar(
        currentIndex: _currentIndex,
        onTabTap: _switchTab,
        onScanTap: _openScanner,
      ),
    );
  }
}

// ── Custom Bottom Nav Bar ──
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
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
              // Center Scan Button
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
              color: isActive ? AppColors.navy : AppColors.textMuted,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? AppColors.navy : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
