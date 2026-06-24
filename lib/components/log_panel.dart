import 'package:flutter/material.dart';
import 'package:lnu_elytra/utils/state.dart';
import 'package:lnu_elytra/src/rust/api/logging.dart';

/// Improved log panel with light theme and resizable width.
class ImprovedLogPanel extends StatefulWidget {
  /// When true (default), a draggable divider is rendered on the left side
  /// so the panel can sit next to another widget (login form, workspace, …).
  /// Set to false when the panel fills the entire screen (e.g. mobile tab).
  final bool showDivider;

  const ImprovedLogPanel({super.key, this.showDivider = true});

  @override
  State<ImprovedLogPanel> createState() => _ImprovedLogPanelState();
}

class _ImprovedLogPanelState extends State<ImprovedLogPanel> {
  static const double _minWidth = 200;
  static const double _maxWidth = 600;
  static const double _defaultWidth = 350;

  double _width = _defaultWidth;

  @override
  Widget build(BuildContext context) {
    if (!widget.showDivider) {
      return const _LogPanelContent();
    }
    return Row(
      children: [
        // Draggable divider
        _buildDragHandle(),
        // Log panel
        SizedBox(width: _width, child: const _LogPanelContent()),
      ],
    );
  }

  Widget _buildDragHandle() {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        onHorizontalDragUpdate: (details) {
          setState(() {
            _width = (_width - details.delta.dx).clamp(_minWidth, _maxWidth);
          });
        },
        child: Container(
          width: 8,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.surface,
                theme.dividerColor.withValues(alpha: 0.5),
                theme.colorScheme.surface,
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
          child: Center(
            child: Container(
              width: 1,
              decoration: BoxDecoration(
                color: theme.dividerColor.withValues(alpha: 0.8),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LogPanelContent extends StatelessWidget {
  const _LogPanelContent();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          _buildHeader(context, theme),
          Divider(height: 1, color: theme.dividerColor),
          const Expanded(child: _LogListView()),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // First row: Title and Clear button
          Row(
            children: [
              Icon(Icons.terminal, color: theme.colorScheme.primary, size: 18),
              const SizedBox(width: 8),
              Text(
                '日志面板',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: '清空',
                icon: Icon(
                  Icons.delete_outline,
                  color: theme.colorScheme.onSurfaceVariant,
                  size: 20,
                ),
                onPressed: logStore.clear,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Second row: Level selector, search box, and counter
          Row(
            children: [
              const _LevelSelector(),
              const SizedBox(width: 8),
              Expanded(child: _SearchBox()),
              const SizedBox(width: 8),
              const _LogCounter(),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchBox extends StatefulWidget {
  @override
  State<_SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<_SearchBox> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 32,
      child: TextField(
        controller: _controller,
        decoration: InputDecoration(
          hintText: '搜索...',
          hintStyle: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          prefixIcon: Icon(
            Icons.search,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: theme.dividerColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: theme.dividerColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: theme.colorScheme.primary),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          isDense: true,
        ),
        style: const TextStyle(fontSize: 12),
        onChanged: (value) {
          logStore.setSearchQuery(value);
        },
      ),
    );
  }
}

class _LogListView extends StatefulWidget {
  const _LogListView();

  @override
  State<_LogListView> createState() => _LogListViewState();
}

class _LogListViewState extends State<_LogListView> {
  final ScrollController _scroll = ScrollController();
  bool _autoScroll = true;

  static const List<String> _kMonoFallback = [
    'Cascadia Mono',
    'Consolas',
    'SF Mono',
    'Menlo',
    'DejaVu Sans Mono',
    'Roboto Mono',
    'monospace',
  ];

  // Light theme colors
  static const Color _kTimeColor = Color(0xFF757575);
  static const Color _kTargetColor = Color(0xFF9E9E9E);
  static const Color _kMessageColor = Color(0xFF424242);

  static const Map<int, Color> _kLevelColors = {
    0: Color(0xFF9E9E9E), // TRACE - gray
    1: Color(0xFF2196F3), // DEBUG - blue
    2: Color(0xFF4CAF50), // INFO - green
    3: Color(0xFFFF9800), // WARN - orange
    4: Color(0xFFF44336), // ERROR - red
  };

  @override
  void initState() {
    super.initState();
    logStore.addListener(_onLogs);
  }

  void _onLogs() {
    if (!_autoScroll || !_scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    logStore.removeListener(_onLogs);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: logStore,
            builder: (context, _) {
              final entries = logStore.visible;
              if (entries.isEmpty) {
                return Center(
                  child: Text(
                    '暂无日志',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                );
              }
              return Scrollbar(
                controller: _scroll,
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  itemCount: entries.length,
                  itemBuilder: (context, i) => _logLine(entries[i]),
                ),
              );
            },
          ),
        ),
        Positioned(right: 12, bottom: 12, child: _autoScrollToggle()),
      ],
    );
  }

  Widget _autoScrollToggle() {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
      shape: const CircleBorder(),
      elevation: 2,
      child: IconButton(
        tooltip: _autoScroll ? '自动滚动开' : '自动滚动关',
        icon: Icon(
          _autoScroll ? Icons.vertical_align_bottom : Icons.lock_outline,
          color: _autoScroll
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
          size: 18,
        ),
        onPressed: () {
          setState(() => _autoScroll = !_autoScroll);
          if (_autoScroll) _onLogs();
        },
      ),
    );
  }

  Widget _logLine(LogEntry e) {
    final color = _kLevelColors[e.level] ?? Colors.white;
    final time = DateTime.fromMillisecondsSinceEpoch(millisOf(e.timeMillis));
    final ts =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: SelectableText.rich(
        TextSpan(
          style: const TextStyle(
            fontFamilyFallback: _kMonoFallback,
            fontSize: 12,
            height: 1.4,
          ),
          children: [
            TextSpan(
              text: '$ts ',
              style: const TextStyle(color: _kTimeColor),
            ),
            TextSpan(
              text: '${kLevelNames[e.level].padRight(5)} ',
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
            TextSpan(
              text: '${e.target}  ',
              style: const TextStyle(color: _kTargetColor),
            ),
            TextSpan(
              text: e.message,
              style: const TextStyle(color: _kMessageColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _LevelSelector extends StatelessWidget {
  const _LevelSelector();

  static const Map<int, Color> _kLevelColors = {
    0: Color(0xFF9E9E9E), // TRACE
    1: Color(0xFF2196F3), // DEBUG
    2: Color(0xFF4CAF50), // INFO
    3: Color(0xFFFF9800), // WARN
    4: Color(0xFFF44336), // ERROR
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: logStore,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '等级',
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.circular(4),
              ),
              child: DropdownButton<int>(
                value: logStore.minLevel,
                dropdownColor: theme.colorScheme.surface,
                underline: const SizedBox.shrink(),
                isDense: true,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: 12,
                ),
                items: [
                  for (int i = 0; i < kLevelNames.length; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text(
                        kLevelNames[i],
                        style: TextStyle(color: _kLevelColors[i]),
                      ),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) logStore.setMinLevel(v);
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LogCounter extends StatelessWidget {
  const _LogCounter();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: logStore,
      builder: (context, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '${logStore.visible.length}/${logStore.totalCount}',
          style: TextStyle(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
