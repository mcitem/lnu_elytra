use std::fmt::Write as _;
use std::sync::OnceLock;
use std::sync::RwLock;
use std::time::{SystemTime, UNIX_EPOCH};

use crate::frb_generated::StreamSink;

use tracing::field::{Field, Visit};
use tracing::{Event, Level, Subscriber};
use tracing_subscriber::layer::Context;
use tracing_subscriber::prelude::*;
use tracing_subscriber::Layer;

/// A single tracing event forwarded from Rust to Dart.
pub struct LogEntry {
    /// Milliseconds since the Unix epoch.
    pub time_millis: i64,
    /// Log level: 0=Trace, 1=Debug, 2=Info, 3=Warn, 4=Error.
    pub level: i32,
    /// The event target (usually the module path).
    pub target: String,
    /// The rendered message (the `message` field plus any other fields).
    pub message: String,
}

fn level_to_i32(level: &Level) -> i32 {
    match *level {
        Level::TRACE => 0,
        Level::DEBUG => 1,
        Level::INFO => 2,
        Level::WARN => 3,
        Level::ERROR => 4,
    }
}

// The single global sink that delivers log entries to Dart. Set once when Dart
// calls `create_log_stream`.
static LOG_SINK: OnceLock<RwLock<Option<StreamSink<LogEntry>>>> = OnceLock::new();

fn sink_cell() -> &'static RwLock<Option<StreamSink<LogEntry>>> {
    LOG_SINK.get_or_init(|| RwLock::new(None))
}

// Collects the `message` field and any extra fields into a single string.
struct MessageVisitor {
    message: String,
}

impl Visit for MessageVisitor {
    fn record_debug(&mut self, field: &Field, value: &dyn std::fmt::Debug) {
        if field.name() == "message" {
            // Prepend the primary message so it leads the line.
            let rendered = format!("{value:?}");
            if self.message.is_empty() {
                self.message = rendered;
            } else {
                self.message = format!("{rendered} {}", self.message);
            }
        } else {
            let _ = write!(self.message, " {}={value:?}", field.name());
        }
    }
}

struct DartSinkLayer;

impl<S: Subscriber> Layer<S> for DartSinkLayer {
    fn on_event(&self, event: &Event<'_>, _ctx: Context<'_, S>) {
        let guard = match sink_cell().read() {
            Ok(g) => g,
            Err(_) => return,
        };
        let Some(sink) = guard.as_ref() else {
            return;
        };

        let mut visitor = MessageVisitor {
            message: String::new(),
        };
        event.record(&mut visitor);

        let meta = event.metadata();
        let entry = LogEntry {
            time_millis: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|d| d.as_millis() as i64)
                .unwrap_or(0),
            level: level_to_i32(meta.level()),
            target: meta.target().to_string(),
            message: visitor.message,
        };

        // Ignore send errors (e.g. the Dart side closed the stream).
        let _ = sink.add(entry);
    }
}

static INIT: OnceLock<()> = OnceLock::new();

/// Open a stream of Rust `tracing` events to Dart.
///
/// The tracing subscriber is installed on the first call; subsequent calls just
/// replace the active sink. The subscriber captures every level (TRACE..ERROR);
/// filtering by level is done on the Dart side so the user can change it live.
pub fn create_log_stream(sink: StreamSink<LogEntry>) {
    {
        let mut guard = sink_cell().write().expect("log sink lock poisoned");
        *guard = Some(sink);
    }

    INIT.get_or_init(|| {
        // Capture all levels; Dart filters for display.
        let subscriber = tracing_subscriber::registry().with(DartSinkLayer);
        // `set_global_default` fails if a subscriber is already set; that's fine.
        let _ = tracing::subscriber::set_global_default(subscriber);
    });

    tracing::info!("https://github.com/mcitem/lnuElytra");
}
