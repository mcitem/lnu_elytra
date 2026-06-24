import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lnu_elytra/utils/state.dart';
import 'package:lnu_elytra/src/rust/third_party/lnu_elytra/flutter.dart';
import 'package:lnu_elytra/src/rust/third_party/lnu_elytra.dart';

/// Strategy for processing the keyword list.
enum GrabStrategy { parallel, sequential }

/// Strategy for handling multiple teaching classes.
enum JxbStrategy { firstOnly, parallel, sequential }

/// Per-keyword runtime status.
enum KeywordStatus { pending, running, success, giveUp, failed }

class _KeywordTask {
  _KeywordTask(this.keyword);
  final String keyword;
  KeywordStatus status = KeywordStatus.pending;
  String note = '';
  int attempts = 0;
}

/// Auto grab tab with collapsible strategy panel.
class AutoGrabTab extends StatefulWidget {
  const AutoGrabTab({super.key});

  @override
  State<AutoGrabTab> createState() => _AutoGrabTabState();
}

class _AutoGrabTabState extends State<AutoGrabTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _inputCtrl = TextEditingController();
  final List<_KeywordTask> _tasks = [];

  GrabStrategy _strategy = GrabStrategy.parallel;
  JxbStrategy _jxbStrategy = JxbStrategy.sequential;
  int _retryIntervalMs = 100;

  bool _running = false;
  bool _cancelRequested = false;
  bool _strategyExpanded = true; // Collapsible strategy panel

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  void _addKeyword() {
    final kw = _inputCtrl.text.trim();
    if (kw.isEmpty) return;
    if (_tasks.any((t) => t.keyword == kw)) {
      _inputCtrl.clear();
      return;
    }
    setState(() {
      _tasks.add(_KeywordTask(kw));
      _inputCtrl.clear();
    });
  }

  void _removeAt(int i) {
    if (_running) return;
    setState(() => _tasks.removeAt(i));
  }

  Future<void> _start() async {
    if (_tasks.isEmpty || _running) return;

    // Collapse strategy panel when starting
    setState(() {
      _running = true;
      _cancelRequested = false;
      _strategyExpanded = false;
      for (final t in _tasks) {
        t.status = KeywordStatus.pending;
        t.note = '';
        t.attempts = 0;
      }
    });

    await _runLoop();

    if (mounted) {
      setState(() {
        _running = false;
        _cancelRequested = false;
      });
    }
  }

  void _cancel() {
    if (!_running) return;
    setState(() {
      _cancelRequested = true;
      for (final t in _tasks) {
        if (!_isSettled(t)) {
          t.status = KeywordStatus.pending;
          t.note = '';
        }
      }
    });
  }

  bool _isSettled(_KeywordTask t) =>
      t.status == KeywordStatus.success || t.status == KeywordStatus.giveUp;

  Future<void> _runLoop() async {
    while (!_cancelRequested) {
      final remaining = _tasks.where((t) => !_isSettled(t)).toList();
      if (remaining.isEmpty) break;

      if (_strategy == GrabStrategy.parallel) {
        await Future.wait(remaining.map((t) => _attempt(t)));
      } else {
        for (final t in remaining) {
          if (_cancelRequested) break;
          await _attempt(t);
          while (!_cancelRequested && !_isSettled(t)) {
            await _delay();
            if (_cancelRequested) break;
            await _attempt(t);
          }
        }
      }

      if (_cancelRequested) break;
      final stillRemaining = _tasks.any((t) => !_isSettled(t));
      if (!stillRemaining) break;
      await _delay();
    }
  }

  Future<void> _delay() async {
    final totalMs = _retryIntervalMs;
    final slices = (totalMs / 100).ceil();
    for (int i = 0; i < slices; i++) {
      if (_cancelRequested) return;
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> _attempt(_KeywordTask t) async {
    if (_cancelRequested) return;
    _update(t, KeywordStatus.running, '查询中...');
    t.attempts++;

    try {
      final course = await session.fetchCourses(t.keyword);
      logStore.info(
        'Course fetched: keyword="${t.keyword}", kchId=${course.kchId}, jxb_count=${course.jxb.length}',
      );

      if (course.jxb.isEmpty) {
        _update(t, KeywordStatus.running, '暂无教学班，重试中（第 ${t.attempts} 次）');
        return;
      }

      switch (_jxbStrategy) {
        case JxbStrategy.firstOnly:
          await _tryJxb(t, course, course.jxb.first);
          break;
        case JxbStrategy.parallel:
          final results = await Future.wait(
            course.jxb.map((jxb) => _tryJxbReturnOutcome(t, course, jxb)),
          );
          final hasSuccess = results.any((r) => r == GrabOutcome.success);
          if (!hasSuccess) {
            final firstResult = results.firstWhere(
              (r) => r != GrabOutcome.success,
              orElse: () => GrabOutcome.retry,
            );
            if (firstResult == GrabOutcome.giveUp) {
              _update(t, KeywordStatus.giveUp, '所有教学班均无法选择（第 ${t.attempts} 次）');
            } else {
              _update(t, KeywordStatus.running, '所有教学班均需重试（第 ${t.attempts} 次）');
            }
          }
          break;
        case JxbStrategy.sequential:
          bool succeeded = false;
          for (final jxb in course.jxb) {
            if (_cancelRequested) return;
            final outcome = await _tryJxbReturnOutcome(t, course, jxb);
            if (outcome == GrabOutcome.success) {
              succeeded = true;
              break;
            }
          }
          if (!succeeded && !_isSettled(t)) {
            _update(
              t,
              KeywordStatus.running,
              '尝试了 ${course.jxb.length} 个教学班，重试中（第 ${t.attempts} 次）',
            );
          }
          break;
      }
    } on FError catch (e) {
      logStore.error('Auto-grab error: keyword="${t.keyword}", ${e.error}');
      if (e.kind == FErrorKind.loginFailed) {
        logStore.error('检测到登录失效，正在退出登录...');
        _cancelRequested = true;
        session.logout();
        return;
      }
      _update(t, KeywordStatus.failed, '错误：${e.error}（第 ${t.attempts} 次，将重试）');
    } catch (e) {
      logStore.error('Exception during grab: keyword="${t.keyword}", error=$e');
      _update(t, KeywordStatus.failed, '错误：$e（第 ${t.attempts} 次，将重试）');
    }
  }

  Future<void> _tryJxb(_KeywordTask t, Course course, Jxb jxb) async {
    final resp = await session.selectCourse(
      courseId: course.kchId,
      courseDoId: jxb.doId,
    );
    logStore.info(
      'SelectCourseResponse: keyword="${t.keyword}", jxbId=${jxb.jxbId}, flag=${resp.flag}, msg=${resp.msg}',
    );
    _applyResponse(t, resp);
  }

  Future<GrabOutcome> _tryJxbReturnOutcome(
    _KeywordTask t,
    Course course,
    Jxb jxb,
  ) async {
    try {
      final resp = await session.selectCourse(
        courseId: course.kchId,
        courseDoId: jxb.doId,
      );
      final outcome = classifyResponse(resp);
      if (outcome == GrabOutcome.success) {
        _applyResponse(t, resp);
      }
      return outcome;
    } on FError catch (e) {
      if (e.kind == FErrorKind.loginFailed) {
        logStore.error('检测到登录失效，正在退出登录...');
        _cancelRequested = true;
        session.logout();
      }
      return GrabOutcome.retry;
    } catch (e) {
      return GrabOutcome.retry;
    }
  }

  void _applyResponse(_KeywordTask t, SelectCourseResponse resp) {
    final outcome = classifyResponse(resp);
    final msg = resp.flag == '1' ? '选课成功' : (resp.msg ?? '未知结果');
    switch (outcome) {
      case GrabOutcome.success:
        _update(t, KeywordStatus.success, msg);
        break;
      case GrabOutcome.giveUp:
        _update(t, KeywordStatus.giveUp, msg);
        break;
      case GrabOutcome.retry:
        _update(t, KeywordStatus.running, '$msg（第 ${t.attempts} 次，将重试）');
        break;
    }
  }

  void _update(_KeywordTask t, KeywordStatus status, String note) {
    if (!mounted) return;
    setState(() {
      t.status = status;
      t.note = note;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Column(
      children: [
        _buildControls(),
        const Divider(height: 1),
        Expanded(child: _buildList()),
      ],
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Input row
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  enabled: !_running,
                  decoration: const InputDecoration(
                    labelText: '输入课程号或精确教学班',
                    hintText: '建议使用精确教学班',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.add_task),
                  ),
                  onSubmitted: (_) => _running ? null : _addKeyword(),
                ),
              ),
              const SizedBox(width: 8),
              // Square button
              SizedBox(
                height: 56,
                width: 56,
                child: FilledButton(
                  onPressed: _running ? null : _addKeyword,
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Icon(Icons.add),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Collapsible strategy panel
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _strategyExpanded
                ? _buildStrategyPanel()
                : const SizedBox.shrink(),
          ),

          // Expand/collapse button
          TextButton.icon(
            onPressed: _running
                ? null
                : () => setState(() => _strategyExpanded = !_strategyExpanded),
            icon: Icon(
              _strategyExpanded ? Icons.expand_less : Icons.expand_more,
            ),
            label: Text(_strategyExpanded ? '收起' : '展开'),
          ),

          const SizedBox(height: 12),

          // Start/Stop buttons
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: (_running || _tasks.isEmpty) ? null : _start,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: _running
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(_running ? '抢课中...' : '启动任务'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: (_running && !_cancelRequested) ? _cancel : null,
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.stop),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(_cancelRequested ? '停止中...' : '取消任务'),
                  ),
                ),
              ),
            ],
          ),

          if (_running)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '任务运行中',
                style: TextStyle(color: Colors.orange, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStrategyPanel() {
    return Column(
      children: [
        _buildKeywordStrategySelector(),
        const SizedBox(height: 12),
        _buildJxbStrategySelector(),
        const SizedBox(height: 12),
        _buildRetryIntervalInput(),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildKeywordStrategySelector() {
    return Row(
      children: [
        const Text('课程策略：'),
        const SizedBox(width: 8),
        Expanded(
          child: SegmentedButton<GrabStrategy>(
            segments: const [
              ButtonSegment(value: GrabStrategy.parallel, label: Text('并行')),
              ButtonSegment(value: GrabStrategy.sequential, label: Text('按顺序')),
            ],
            selected: {_strategy},
            onSelectionChanged: _running
                ? null
                : (s) => setState(() => _strategy = s.first),
          ),
        ),
      ],
    );
  }

  Widget _buildJxbStrategySelector() {
    return Row(
      children: [
        const Text('教学班策略：'),
        const SizedBox(width: 8),
        Expanded(
          child: SegmentedButton<JxbStrategy>(
            segments: const [
              ButtonSegment(value: JxbStrategy.firstOnly, label: Text('仅第一个')),
              ButtonSegment(value: JxbStrategy.parallel, label: Text('并行')),
              ButtonSegment(value: JxbStrategy.sequential, label: Text('串行')),
            ],
            selected: {_jxbStrategy},
            onSelectionChanged: _running
                ? null
                : (s) => setState(() => _jxbStrategy = s.first),
          ),
        ),
      ],
    );
  }

  Widget _buildRetryIntervalInput() {
    return Row(
      children: [
        const Text('重试间隔(ms)：'),
        const SizedBox(width: 8),
        SizedBox(
          width: 120,
          child: TextField(
            enabled: !_running,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            controller: TextEditingController(text: '$_retryIntervalMs')
              ..selection = TextSelection.fromPosition(
                TextPosition(offset: '$_retryIntervalMs'.length),
              ),
            onChanged: (v) {
              final val = int.tryParse(v);
              if (val != null && val >= 0) {
                setState(() => _retryIntervalMs = val);
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildList() {
    if (_tasks.isEmpty) {
      return const Center(
        child: Text('添加一个或多个关键字，然后启动任务', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _tasks.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) => _buildTaskTile(i, _tasks[i]),
    );
  }

  Widget _buildTaskTile(int i, _KeywordTask t) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _buildStatusIcon(t.status),
      title: Text(t.keyword),
      subtitle: t.note.isEmpty ? null : Text(t.note),
      trailing: _running
          ? null
          : IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: '移除',
              onPressed: () => _removeAt(i),
            ),
    );
  }

  Widget _buildStatusIcon(KeywordStatus s) {
    switch (s) {
      case KeywordStatus.pending:
        return const Icon(Icons.schedule, color: Colors.grey);
      case KeywordStatus.running:
        return const SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case KeywordStatus.success:
        return const Icon(Icons.check_circle, color: Colors.green);
      case KeywordStatus.giveUp:
        return const Icon(Icons.do_not_disturb_on, color: Colors.redAccent);
      case KeywordStatus.failed:
        return const Icon(Icons.error_outline, color: Colors.orange);
    }
  }
}
