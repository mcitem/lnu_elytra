import 'package:flutter/material.dart';
import 'package:lnu_elytra/views/home/auto_grab/auto_grab_tab.dart';
import 'package:lnu_elytra/views/home/manual_grab/manual_grab_tab.dart';

/// Main grab workspace with tabs for auto and manual grab.
class GrabWorkspace extends StatelessWidget {
  const GrabWorkspace({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          // Tab bar
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 1,
                ),
              ),
            ),
            child: const TabBar(
              tabs: [
                Tab(text: '自动抢课'),
                Tab(text: '手动抢课'),
              ],
            ),
          ),

          // Tab views
          const Expanded(
            child: TabBarView(children: [AutoGrabTab(), ManualGrabTab()]),
          ),
        ],
      ),
    );
  }
}
