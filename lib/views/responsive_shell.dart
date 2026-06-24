import 'package:flutter/material.dart';
import 'package:lnu_elytra/components/log_panel.dart';
import 'package:lnu_elytra/components/toast.dart';
import 'package:lnu_elytra/utils/state.dart';
import 'package:lnu_elytra/views/home/grab_workspace.dart';
import 'package:lnu_elytra/views/login/login_page.dart';
import 'package:url_launcher/url_launcher.dart';

/// Breakpoint for responsive layout: below this is mobile, above is desktop.
const double kResponsiveBreakpoint = 800;

/// Main responsive shell.
///
/// Shows the [LoginPage] until the user logs in, then the grab workspace with a
/// live log panel: a two-column layout on desktop, a tabbed layout on mobile.
class ResponsiveShell extends StatefulWidget {
  const ResponsiveShell({super.key});

  @override
  State<ResponsiveShell> createState() => _ResponsiveShellState();
}

class _ResponsiveShellState extends State<ResponsiveShell> {
  int _mobileTabIndex = 0;
  bool _checkingLogin = false;

  Future<void> _checkLogin() async {
    setState(() => _checkingLogin = true);
    try {
      final info = await session.verifyLogin();
      if (!mounted) return;
      toaster.success('登录有效，账号：$info');
    } catch (e) {
      if (!mounted) return;
      toaster.error('登录已失效，正在退出：$e');
      // Session is no longer valid — clear it so the shell switches back to
      // the login page.
      session.logout();
    } finally {
      if (mounted) setState(() => _checkingLogin = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= kResponsiveBreakpoint;
            if (!session.isLoggedIn) {
              return isWide
                  ? _buildDesktopLoginLayout()
                  : _buildMobileLoginLayout();
            }
            return isWide ? _buildDesktopLayout() : _buildMobileLayout();
          },
        );
      },
    );
  }

  // ── Desktop login: login form + log side-by-side ──
  Widget _buildDesktopLoginLayout() {
    return Scaffold(
      body: Row(
        children: [
          const Expanded(child: LoginPage()),
          const ImprovedLogPanel(),
        ],
      ),
    );
  }

  // ── Mobile login: bottom tabs for login form and log panel ──
  Widget _buildMobileLoginLayout() {
    return Scaffold(
      body: IndexedStack(
        index: _mobileTabIndex,
        children: [
          const LoginPage(),
          const ImprovedLogPanel(showDivider: false),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _mobileTabIndex,
        onTap: (index) => setState(() => _mobileTabIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.login), label: '登录'),
          BottomNavigationBarItem(icon: Icon(Icons.terminal), label: '日志面板'),
        ],
      ),
    );
  }

  // Desktop layout: app bar + main + logs (side-by-side)
  Widget _buildDesktopLayout() {
    return Scaffold(
      body: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                _buildDesktopAppBar(),
                const Expanded(child: GrabWorkspace()),
              ],
            ),
          ),
          const ImprovedLogPanel(),
        ],
      ),
    );
  }

  // Mobile layout: app bar + main + bottom TabBar for logs
  Widget _buildMobileLayout() {
    return Scaffold(
      appBar: _buildMobileAppBar(),
      body: IndexedStack(
        index: _mobileTabIndex,
        children: [const GrabWorkspace(), _buildMobileLogScreen()],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _mobileTabIndex,
        onTap: (index) => setState(() => _mobileTabIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.rocket_launch),
            label: '抢课任务',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.terminal), label: '日志面板'),
        ],
      ),
    );
  }

  Widget _buildDesktopAppBar() {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              session.username ?? '未登录',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            icon: _checkingLogin
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: '检测登录状态',
            onPressed: _checkingLogin ? null : _checkLogin,
          ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: '帮助',
            onPressed: () {
              launchUrl(Uri.parse('https://lnu-elytra.mcitem.net/'));
            },
          ),
          IconButton(
            icon: const Icon(Icons.code),
            tooltip: 'GitHub',
            onPressed: () {
              launchUrl(Uri.parse('https://github.com/mcitem/lnuElytra'));
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '退出登录',
            onPressed: () => session.logout(),
          ),
        ],
      ),
    );
  }

  AppBar _buildMobileAppBar() {
    return AppBar(
      title: Text(session.username ?? '未登录'),
      actions: [
        IconButton(
          icon: _checkingLogin
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          tooltip: '检测登录状态',
          onPressed: _checkingLogin ? null : _checkLogin,
        ),
        IconButton(
          icon: const Icon(Icons.help_outline),
          tooltip: '帮助',
          onPressed: () {
            launchUrl(Uri.parse('https://lnu-elytra.mcitem.net/'));
          },
        ),
        IconButton(
          icon: const Icon(Icons.code),
          tooltip: 'GitHub',
          onPressed: () {
            launchUrl(Uri.parse('https://github.com/mcitem/lnuElytra'));
          },
        ),
        IconButton(
          icon: const Icon(Icons.logout),
          tooltip: '退出登录',
          onPressed: () => session.logout(),
        ),
      ],
    );
  }

  Widget _buildMobileLogScreen() {
    return const ImprovedLogPanel(showDivider: false);
  }
}
