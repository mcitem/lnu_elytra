import 'package:flutter/material.dart';
import 'package:lnu_elytra/components/toast.dart';
import 'package:lnu_elytra/utils/state.dart';
import 'package:lnu_elytra/src/rust/third_party/lnu_elytra/flutter.dart';
import 'package:lnu_elytra/src/rust/third_party/lnu_elytra.dart';

/// Manual grab tab with search and course selection.
class ManualGrabTab extends StatefulWidget {
  const ManualGrabTab({super.key});

  @override
  State<ManualGrabTab> createState() => _ManualGrabTabState();
}

class _ManualGrabTabState extends State<ManualGrabTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _queryCtrl = TextEditingController();

  bool _searching = false;
  String? _error;
  Course? _course;
  String _lastQuery = '';
  String? _grabbingDoId;

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _queryCtrl.text.trim();

    setState(() {
      _searching = true;
      _error = null;
    });

    try {
      final course = await session.fetchCourses(q);
      setState(() {
        _course = course;
        _lastQuery = q;
      });
    } on FError catch (e) {
      if (e.kind == FErrorKind.loginFailed) {
        logStore.error('检测到登录失效，正在退出登录...');
        session.logout();
        return;
      }
      setState(() {
        _course = null;
        _error = switch (e.kind) {
          FErrorKind.notyetStarted => '选课尚未开放，请稍后重试',
          FErrorKind.jxbNotFound => '未找到教学班：$q',
          _ => '搜索失败：${e.error}',
        };
      });
    } catch (e) {
      setState(() {
        _course = null;
        _error = '搜索失败：$e';
      });
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _grab(Course course, Jxb jxb) async {
    setState(() => _grabbingDoId = jxb.doId);
    try {
      final resp = await session.selectCourse(
        courseId: course.kchId,
        courseDoId: jxb.doId,
      );
      if (!mounted) return;
      _showResult(resp);
    } on FError catch (e) {
      if (e.kind == FErrorKind.loginFailed) {
        logStore.error('检测到登录失效，正在退出登录...');
        session.logout();
        return;
      }
      if (mounted) {
        _snack(
          e.kind == FErrorKind.notyetStarted
              ? '选课尚未开放（init 未就绪），请稍后重试'
              : '抢课失败：${e.error}',
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) _snack('抢课失败：$e', isError: true);
    } finally {
      if (mounted) setState(() => _grabbingDoId = null);
    }
  }

  void _showResult(SelectCourseResponse resp) {
    final outcome = classifyResponse(resp);
    final ok = outcome == GrabOutcome.success;
    final text = resp.flag == '1' ? '选课成功' : (resp.msg ?? '选课失败（未知原因）');
    _snack(text, isError: !ok);
  }

  void _snack(String msg, {bool isError = false}) {
    if (isError) {
      toaster.error(msg);
    } else {
      toaster.success(msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _queryCtrl,
                  enabled: !_searching,
                  decoration: const InputDecoration(
                    labelText: '请输入教学班',
                    hintText: '例：(2025-2026-2)-77101504-02',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                  ),
                  onSubmitted: (_) => _searching ? null : _search(),
                ),
              ),
              const SizedBox(width: 8),
              // Square search button
              SizedBox(
                height: 56,
                width: 56,
                child: FilledButton(
                  onPressed: _searching ? null : _search,
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _searching
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                ),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
        Expanded(child: _buildResults()),
      ],
    );
  }

  Widget _buildResults() {
    final course = _course;
    if (course == null) {
      return const Center(
        child: Text('输入关键字后点击搜索', style: TextStyle(color: Colors.grey)),
      );
    }
    if (course.jxb.isEmpty) {
      return Center(
        child: Text(
          '「$_lastQuery」没有可选教学班',
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            '「$_lastQuery」  课程号 ${course.kchId}  共 ${course.jxb.length} 个教学班',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: course.jxb.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) => _buildJxbTile(course, course.jxb[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildJxbTile(Course course, Jxb jxb) {
    final grabbing = _grabbingDoId == jxb.doId;
    final anyGrabbing = _grabbingDoId != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  jxb.jxbId,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                _buildMeta(Icons.person_outline, jxb.jsxx),
                const SizedBox(height: 2),
                _buildMeta(Icons.schedule, jxb.sksj),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 40,
            child: FilledButton(
              onPressed: anyGrabbing ? null : () => _grab(course, jxb),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: grabbing
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('抢课'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeta(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text.isEmpty ? '—' : text,
            style: const TextStyle(fontSize: 13, color: Colors.black87),
          ),
        ),
      ],
    );
  }
}
