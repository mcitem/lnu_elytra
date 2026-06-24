import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import 'package:lnu_elytra/src/rust/api/logging.dart';
import 'package:lnu_elytra/src/rust/third_party/lnu_elytra/flutter.dart';
import 'package:lnu_elytra/src/rust/third_party/lnu_elytra.dart';

/// Names for the integer log levels emitted by the Rust side.
/// 0=Trace, 1=Debug, 2=Info, 3=Warn, 4=Error.
const List<String> kLevelNames = ['TRACE', 'DEBUG', 'INFO', 'WARN', 'ERROR'];

/// Default minimum level shown in the tracing panel: INFO.
const int kDefaultMinLevel = 2;

int millisOf(Object v) => v is BigInt ? v.toInt() : v as int;

/// A selectable backend endpoint. A null [url] means the library default
/// (built via `FClient.newInstance`); a non-null [url] uses
/// `FClient.newWithBase`.
class Endpoint {
  final String label;
  final String url;
  const Endpoint(this.label, this.url);
}

/// Preset endpoints offered in the selector, Bitwarden-style.
const List<Endpoint> kPresetEndpoints = [
  Endpoint('岭南师范学院', 'http://jw.lingnan.edu.cn'),
  Endpoint('岭南师范学院IPV4', 'http://202.192.143.203'),
  Endpoint('岭南师范学院HTTPS', 'https://jw.lingnan.edu.cn'),
  Endpoint('广州商学院', 'http://jwxt.gcc.edu.cn'),
  Endpoint('广州商学院HTTPS', 'https://jwxt.gcc.edu.cn'),
];

/// The single user session: holds the logged-in [FClient] and login state.
///
/// Nothing is persisted — the client and login state live only in memory, so
/// the user must log in again after a restart.
class AppSession extends ChangeNotifier {
  /// The username used to log in (the student ID / account name).
  String? username;

  /// The client, attached at login time. `null` until login and after logout.
  FClient? _client;

  /// Whether `init()` has completed successfully on the current client.
  bool inited = false;

  /// In-flight `init()` so concurrent callers share a single call.
  Future<void>? _initFuture;

  bool get isLoggedIn => username != null;
  FClient? get client => _client;

  /// Attach a freshly-built, logged-in client for [username].
  void attachClient(String username, FClient client) {
    this.username = username;
    _client = client;
    inited = false;
    _initFuture = null;
    notifyListeners();
  }

  /// Drop the client and all login state.
  Future<void> logout() async {
    _client = null;
    username = null;
    inited = false;
    _initFuture = null;
    notifyListeners();
  }

  /// Run `init()` at most once for the current client.
  ///
  /// Only the course-selection paths need it, so it's invoked lazily right
  /// before those calls (see [fetchCourses] / [selectCourse]). On failure the
  /// cached future is cleared so a later call retries.
  Future<void> ensureInit() {
    if (inited) return Future.value();
    return _initFuture ??= () async {
      try {
        final c = _client;
        if (c == null) throw StateError('not logged in');
        await c.init();
        inited = true;
        notifyListeners();
      } catch (_) {
        _initFuture = null;
        rethrow;
      }
    }();
  }

  /// Search courses, running [ensureInit] first.
  Future<Course> fetchCourses(String q) async {
    await ensureInit();
    final c = _client;
    if (c == null) throw StateError('not logged in');
    return c.fetchCourses(q: q);
  }

  /// Submit a course selection, running [ensureInit] first.
  Future<SelectCourseResponse> selectCourse({
    required String courseId,
    required String courseDoId,
  }) async {
    await ensureInit();
    final c = _client;
    if (c == null) throw StateError('not logged in');
    return c.selectCourse(courseId: courseId, courseDoId: courseDoId);
  }

  /// Verify the current session is still valid by calling `checkLogin`.
  Future<String> verifyLogin() async {
    final c = _client;
    if (c == null) throw StateError('not logged in');
    return c.checkLogin();
  }
}

/// Buffers tracing events streamed from Rust and exposes a level filter.
class LogStore extends ChangeNotifier {
  static const int maxEntries = 5000;

  final List<LogEntry> _entries = [];
  StreamSubscription<LogEntry>? _sub;

  /// Minimum level to display; entries below this are hidden (not dropped).
  int minLevel = kDefaultMinLevel;

  /// Current search query; entries whose message and target both fail to
  /// contain this substring (case-insensitive) are hidden. Empty = no filter.
  String searchQuery = '';

  bool _notifyScheduled = false;

  /// Subscribe to the Rust tracing stream. Safe to call once.
  void start() {
    _sub ??= createLogStream().listen((e) {
      _entries.add(e);
      if (_entries.length > maxEntries) {
        _entries.removeRange(0, _entries.length - maxEntries);
      }
      _scheduleNotify();
    });
  }

  /// Append a log entry produced on the Dart side, mirroring the buffering
  /// behaviour of the Rust stream. [level] uses the same scale as
  /// [LogEntry.level] (0=Trace .. 4=Error); it defaults to INFO.
  void write(
    String message, {
    int level = kDefaultMinLevel,
    String target = 'dart',
    DateTime? time,
  }) {
    final millis = (time ?? DateTime.now()).millisecondsSinceEpoch;
    _entries.add(
      LogEntry(
        timeMillis: PlatformInt64Util.from(millis),
        level: level,
        target: target,
        message: message,
      ),
    );
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
    _scheduleNotify();
  }

  /// Convenience wrappers around [write] for the common levels.
  void trace(String message, {String target = 'dart'}) =>
      write(message, level: 0, target: target);
  void debug(String message, {String target = 'dart'}) =>
      write(message, level: 1, target: target);
  void info(String message, {String target = 'dart'}) =>
      write(message, level: 2, target: target);
  void warn(String message, {String target = 'dart'}) =>
      write(message, level: 3, target: target);
  void error(String message, {String target = 'dart'}) =>
      write(message, level: 4, target: target);

  List<LogEntry> get visible {
    final q = searchQuery.toLowerCase();
    return _entries
        .where((e) {
          if (e.level < minLevel) return false;
          if (q.isEmpty) return true;
          return e.message.toLowerCase().contains(q) ||
              e.target.toLowerCase().contains(q);
        })
        .toList(growable: false);
  }

  int get totalCount => _entries.length;

  void setMinLevel(int level) {
    minLevel = level;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    searchQuery = query;
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  /// Render every buffered entry as plain text, ignoring the level filter.
  /// Used by the "导出完整日志" action.
  String exportAll() {
    final buf = StringBuffer();
    for (final e in _entries) {
      final t = DateTime.fromMillisecondsSinceEpoch(millisOf(e.timeMillis));
      final level = (e.level >= 0 && e.level < kLevelNames.length)
          ? kLevelNames[e.level]
          : e.level.toString();
      buf.writeln(
        '${t.toIso8601String()}  ${level.padRight(5)}  ${e.target}  ${e.message}',
      );
    }
    return buf.toString();
  }

  // Coalesce bursts of log events into a single rebuild per microtask.
  void _scheduleNotify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    Future.microtask(() {
      _notifyScheduled = false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// Classification of a [SelectCourseResponse] for the auto-grab loop.
enum GrabOutcome {
  /// Got the class (or already had it): stop trying this keyword.
  success,

  /// Hard limit reached: give up on this keyword.
  giveUp,

  /// Transient condition (not open / too frequent / error): keep retrying.
  retry,
}

GrabOutcome classifyResponse(SelectCourseResponse r) {
  if (r.flag == '1') return GrabOutcome.success;
  final msg = r.msg ?? '';
  // "一门课程只能选一个教学班，不可再选！" -> already have a class for this course.
  if (msg.contains('只能选一个教学班')) return GrabOutcome.success;
  // "超过体育分项本学期本专业最高选课门次限制，不可选！" -> hard limit.
  if (msg.contains('超过')) return GrabOutcome.giveUp;
  // "对不起，当前未开放选课！" / "选课频率过高，请稍后重试！" / other -> retry.
  return GrabOutcome.retry;
}

/// Global singletons.
final session = AppSession();
final logStore = LogStore();
