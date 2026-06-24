//! Android TLS certificate verifier initialization.
//!
//! The Kotlin `MyPlugin` loads `librust_lib_lnu_elytra.so` in its companion
//! `init {}` block and calls `init_android(applicationContext)` from
//! `onAttachedToEngine`. This module:
//!
//! 1. Stores the `JavaVM` into `ndk_context` (so other crates can reach it).
//! 2. Creates global references to the application `Context` and its
//!    `ClassLoader`, and stores them in module-level statics.
//! 3. Hands a [`NdkRuntime`] (which reads from those statics) to
//!    `rustls_platform_verifier::android::init_with_runtime`.

use std::ffi::c_void;
use std::sync::OnceLock;

use jni::objects::{Global, JClassLoader, JObject, JValue};
use jni::sys::jint;
use jni::{jni_sig, jni_str, Env, JavaVM};

/// Log a message via Android's `android.util.Log` so it appears in logcat.
/// Works even before flutter_rust_bridge's tracing subscriber is set up.
fn android_log(env: &mut Env, level: &str, tag: &str, msg: &str) {
    let log_class = match env.find_class(jni_str!("android/util/Log")) {
        Ok(c) => c,
        Err(_) => return,
    };
    let j_tag = match env.new_string(tag) {
        Ok(s) => s,
        Err(_) => return,
    };
    let j_msg = match env.new_string(msg) {
        Ok(s) => s,
        Err(_) => return,
    };
    let level_int: jint = match level {
        "ERROR" => 6,
        "WARN" => 5,
        "INFO" => 4,
        "DEBUG" => 3,
        _ => 4,
    };
    let _ = env.call_method(
        &log_class,
        jni_str!("println"),
        jni_sig!("(ILjava/lang/String;Ljava/lang/String;)I"),
        &[
            JValue::from(level_int),
            JValue::from(&j_tag),
            JValue::from(&j_msg),
        ],
    );
}

// ---------------------------------------------------------------------------
// Statics backing [`NdkRuntime`]
// ---------------------------------------------------------------------------

static CONTEXT: OnceLock<Global<JObject<'static>>> = OnceLock::new();
static LOADER: OnceLock<Global<JClassLoader<'static>>> = OnceLock::new();
static JAVA_VM: OnceLock<JavaVM> = OnceLock::new();

/// Zero-sized [`rustls_platform_verifier::android::Runtime`] that reads its
/// handles from the statics above. A single static instance is handed to
/// `init_with_runtime`.
struct NdkRuntime;

unsafe impl Sync for NdkRuntime {}
unsafe impl Send for NdkRuntime {}

impl rustls_platform_verifier::android::Runtime for NdkRuntime {
    fn java_vm(&self) -> &JavaVM {
        JAVA_VM.get().expect("JavaVM not initialized")
    }

    fn context(&self) -> &Global<JObject<'static>> {
        CONTEXT.get().expect("rustls context not initialized")
    }

    fn class_loader(&self) -> &Global<JClassLoader<'static>> {
        LOADER.get().expect("rustls class loader not initialized")
    }
}

static NDK_RUNTIME: NdkRuntime = NdkRuntime;

// ---------------------------------------------------------------------------
// JNI entry point
// ---------------------------------------------------------------------------

/// Called from Kotlin `MyPlugin.init_android(applicationContext)`.
///
/// Captures the `JavaVM` and application `Context` into `ndk_context` (for
/// other crates) and into module-level statics (for [`NdkRuntime`]). Then
/// initializes `rustls-platform-verifier` with the [`NdkRuntime`].
///
/// Must be called exactly once, before any TLS connection is made.
#[no_mangle]
pub unsafe extern "C" fn Java_com_mcitem_lnu_1elytra_MyPlugin_init_1android(
    mut unowned_env: jni::EnvUnowned<'_>,
    _class: jni::sys::jobject,
    raw_context: jni::sys::jobject,
) {
    let _ = unowned_env.with_env(|env| -> Result<(), jni::errors::Error> {
        android_log(env, "INFO", "RustTLS", "init_android called");

        let context = unsafe { JObject::from_raw(env, raw_context) };

        // ---- ndk_context (for other crates) --------------------------------
        let vm = env.get_java_vm()?;
        let vm_ptr = vm.get_raw() as *mut c_void;
        let ctx_ptr = unsafe { JObject::from_raw(env, raw_context) }.as_raw() as *mut c_void;
        ndk_context::initialize_android_context(vm_ptr, ctx_ptr);

        // ---- our own statics (for NdkRuntime) ------------------------------
        let _ = JAVA_VM.set(vm);

        let loader_obj = env
            .call_method(
                &context,
                jni_str!("getClassLoader"),
                jni_sig!("()Ljava/lang/ClassLoader;"),
                &[],
            )?
            .l()?;
        let loader = env.cast_local::<JClassLoader>(loader_obj)?;

        let ctx_global: Global<JObject<'static>> = env.new_global_ref(&context)?;
        let loader_global: Global<JClassLoader<'static>> = env.new_global_ref(&loader)?;

        let _ = CONTEXT.set(ctx_global);
        let _ = LOADER.set(loader_global);

        // ---- hand to rustls-platform-verifier ------------------------------
        rustls_platform_verifier::android::init_with_runtime(&NDK_RUNTIME);

        android_log(env, "INFO", "RustTLS", "init completed successfully");
        Ok(())
    });
}
