#define GL_SILENCE_DEPRECATION
#import <AppKit/AppKit.h>
#include <jni.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <OpenGL/OpenGL.h>
#include <OpenGL/gl.h>
#include <pthread.h>

#include <algorithm>
#include <bit>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <functional>
#include <mutex>
#include <string>
#include <vector>

namespace {

using WindowHandle = unsigned long;
using InitializeBridge = bool (*)(const char*);
using UninitializeBridge = bool (*)();
using InstanceWindowGL = bool (*)(WindowHandle*, unsigned long);
using GetDisplays = bool (*)(int*, unsigned long*);
using GetQuiltSettings = bool (*)(WindowHandle, float*, int*, int*, int*, int*);
using GetViewCone = bool (*)(WindowHandle, float*);
using GetDisplayForWindow = bool (*)(WindowHandle, unsigned long*);
using GetWideString = bool (*)(WindowHandle, int*, wchar_t*);
using GetMaxTextureSize = bool (*)(WindowHandle, unsigned long*);
using PresentTexture = bool (*)(
    WindowHandle, unsigned long long, int, unsigned long, unsigned long,
    unsigned long, unsigned long, float, float);
using SetTexture = PresentTexture;
using ShowWindow = bool (*)(WindowHandle, bool);
using SaveTexture = bool (*)(
    WindowHandle, char*, unsigned long long, int, unsigned long, unsigned long);

struct Session {
  void* module = nullptr;
  WindowHandle window = 0;
  InitializeBridge initialize = nullptr;
  UninitializeBridge uninitialize = nullptr;
  InstanceWindowGL instanceWindow = nullptr;
  GetQuiltSettings getQuiltSettings = nullptr;
  GetViewCone getViewCone = nullptr;
  GetDisplayForWindow getDisplayForWindow = nullptr;
  GetWideString getDeviceName = nullptr;
  GetWideString getDeviceSerial = nullptr;
  GetMaxTextureSize getMaxTextureSize = nullptr;
  PresentTexture presentTexture = nullptr;
  SetTexture setTexture = nullptr;
  ShowWindow showWindow = nullptr;
  SaveTexture saveTexture = nullptr;
  NSWindow* nativeWindow = nil;
  unsigned long long registeredTexture = 0;
  int registeredPixelFormat = 0;
  unsigned long registeredWidth = 0;
  unsigned long registeredHeight = 0;
  unsigned long registeredColumns = 0;
  unsigned long registeredRows = 0;
  float registeredAspect = 0.0f;
  float registeredZoom = 0.0f;
  bool windowShown = false;
};

std::mutex bridgeMutex;
int bridgeReferenceCount = 0;

class CglContextGuard {
 public:
  CglContextGuard() : context_(CGLGetCurrentContext()) {}
  ~CglContextGuard() {
    if (context_ != nullptr && CGLGetCurrentContext() != context_) {
      CGLSetCurrentContext(context_);
    }
  }
  bool available() const { return context_ != nullptr; }

 private:
  CGLContextObj context_;
};

struct MainThreadInvocation {
  CGLContextObj context;
  std::function<void()> work;
  bool contextWasBound = false;
};

void invokeWithCglContext(void* opaque) {
  auto* invocation = static_cast<MainThreadInvocation*>(opaque);
  CGLContextObj previousContext = CGLGetCurrentContext();
  if (invocation->context != nullptr) {
    if (CGLLockContext(invocation->context) != kCGLNoError) return;
    if (CGLSetCurrentContext(invocation->context) != kCGLNoError) {
      CGLUnlockContext(invocation->context);
      return;
    }
  }
  invocation->contextWasBound = true;
  invocation->work();
  if (invocation->context != nullptr) {
    CGLSetCurrentContext(previousContext);
    CGLUnlockContext(invocation->context);
  }
}

bool runOnAppKitThread(CGLContextObj context, std::function<void()> work) {
  if (pthread_main_np() != 0) {
    work();
    return true;
  }

  // JOGL keeps the Processing context current and locked while setup()/draw()
  // executes. AppKit may need that same lock to service a pending NSOpenGLContext
  // update before it can run our main-queue block, so release both ownerships.
  if (context != nullptr) {
    if (CGLSetCurrentContext(nullptr) != kCGLNoError) return false;
    if (CGLUnlockContext(context) != kCGLNoError) {
      CGLSetCurrentContext(context);
      return false;
    }
  }
  MainThreadInvocation invocation{context, std::move(work)};
  dispatch_sync_f(dispatch_get_main_queue(), &invocation, invokeWithCglContext);
  bool restored = true;
  if (context != nullptr) {
    restored = CGLLockContext(context) == kCGLNoError;
    if (restored && CGLSetCurrentContext(context) != kCGLNoError) {
      CGLUnlockContext(context);
      restored = false;
    }
  }
  return invocation.contextWasBound && restored;
}

bool isBridgeWindow(NSWindow* window) {
  Class bridgeWindowClass = NSClassFromString(@"MacintoshWindow");
  return bridgeWindowClass != Nil && [window isKindOfClass:bridgeWindowClass];
}

std::vector<NSWindow*> bridgeWindows() {
  std::vector<NSWindow*> result;
  for (NSWindow* window in NSApp.windows) {
    if (isBridgeWindow(window)) result.push_back(window);
  }
  return result;
}

NSWindow* findNewBridgeWindow(const std::vector<NSWindow*>& previousWindows) {
  for (NSWindow* window in NSApp.windows) {
    if (isBridgeWindow(window)
        && std::find(previousWindows.begin(), previousWindows.end(), window)
            == previousWindows.end()) {
      return window;
    }
  }
  return nil;
}

bool fitBridgeWindowToDisplay(Session* session) {
  @autoreleasepool {
    NSWindow* bridgeWindow = session->nativeWindow;
    if (bridgeWindow == nil) {
      std::vector<NSWindow*> windows = bridgeWindows();
      if (!windows.empty()) bridgeWindow = windows.back();
    }
    if (bridgeWindow == nil) return false;

    NSRect oldFrame = bridgeWindow.frame;
    size_t expectedPixelWidth = static_cast<size_t>(std::llround(oldFrame.size.width));
    size_t expectedPixelHeight = static_cast<size_t>(std::llround(oldFrame.size.height));
    NSScreen* targetScreen = nil;
    CGFloat closestHorizontalDistance = CGFLOAT_MAX;
    for (NSScreen* screen in [NSScreen screens]) {
      NSNumber* screenNumber = screen.deviceDescription[@"NSScreenNumber"];
      if (screenNumber == nil) continue;
      CGDirectDisplayID screenId = screenNumber.unsignedIntValue;
      if (CGDisplayPixelsWide(screenId) == expectedPixelWidth
          && CGDisplayPixelsHigh(screenId) == expectedPixelHeight) {
        CGFloat distance = std::abs(screen.frame.origin.x - oldFrame.origin.x);
        if (targetScreen == nil || distance < closestHorizontalDistance) {
          targetScreen = screen;
          closestHorizontalDistance = distance;
        }
      }
    }
    if (targetScreen == nil) targetScreen = bridgeWindow.screen;
    if (targetScreen == nil) return false;

    NSRect targetFrame = targetScreen.frame;
    bridgeWindow.styleMask = NSWindowStyleMaskBorderless;
    [bridgeWindow setFrame:targetFrame display:YES];
    [bridgeWindow orderFrontRegardless];
    return true;
  }
}

void throwJava(JNIEnv* env, const char* className, const std::string& message) {
  jclass exceptionClass = env->FindClass(className);
  if (exceptionClass != nullptr) env->ThrowNew(exceptionClass, message.c_str());
}

std::string javaString(JNIEnv* env, jstring value) {
  if (value == nullptr) return "Processing2Hologram";
  const char* chars = env->GetStringUTFChars(value, nullptr);
  if (chars == nullptr) return "";
  std::string result(chars);
  env->ReleaseStringUTFChars(value, chars);
  return result;
}

void appendUtf8(std::string* output, uint32_t codePoint) {
  if (codePoint <= 0x7f) {
    output->push_back(static_cast<char>(codePoint));
  } else if (codePoint <= 0x7ff) {
    output->push_back(static_cast<char>(0xc0 | (codePoint >> 6)));
    output->push_back(static_cast<char>(0x80 | (codePoint & 0x3f)));
  } else if (codePoint <= 0xffff) {
    output->push_back(static_cast<char>(0xe0 | (codePoint >> 12)));
    output->push_back(static_cast<char>(0x80 | ((codePoint >> 6) & 0x3f)));
    output->push_back(static_cast<char>(0x80 | (codePoint & 0x3f)));
  } else {
    output->push_back(static_cast<char>(0xf0 | (codePoint >> 18)));
    output->push_back(static_cast<char>(0x80 | ((codePoint >> 12) & 0x3f)));
    output->push_back(static_cast<char>(0x80 | ((codePoint >> 6) & 0x3f)));
    output->push_back(static_cast<char>(0x80 | (codePoint & 0x3f)));
  }
}

std::string bridgeLibraryPath() {
  const char* overridePath = std::getenv("LOOKING_GLASS_BRIDGE_LIBRARY");
  if (overridePath != nullptr && overridePath[0] != '\0') return overridePath;

  std::vector<std::filesystem::path> candidates;
  std::error_code error;
  for (const auto& entry : std::filesystem::directory_iterator("/Applications", error)) {
    std::string name = entry.path().filename().string();
    if (name.starts_with("Looking Glass Bridge") && name.ends_with(".app")) {
      std::filesystem::path library =
          entry.path() / "Contents/MacOS/libbridge_inproc.dylib";
      if (std::filesystem::is_regular_file(library, error)) candidates.push_back(library);
    }
  }
  std::sort(candidates.begin(), candidates.end());
  return candidates.empty() ? "libbridge_inproc.dylib" : candidates.back().string();
}

void* loadBridgeModule(std::string* error) {
  std::string path = bridgeLibraryPath();
  void* module = dlopen(path.c_str(), RTLD_NOW | RTLD_LOCAL);
  if (module == nullptr) {
    const char* detail = dlerror();
    *error = "Could not load " + path + (detail == nullptr ? "" : ": " + std::string(detail));
  }
  return module;
}

template <typename Function>
Function resolve(void* module, const char* name) {
  return reinterpret_cast<Function>(dlsym(module, name));
}

bool resolveAll(Session* session) {
  session->initialize = resolve<InitializeBridge>(session->module, "initialize_bridge");
  session->uninitialize = resolve<UninitializeBridge>(session->module, "uninitialize_bridge");
  session->instanceWindow = resolve<InstanceWindowGL>(session->module, "instance_window_gl");
  session->getQuiltSettings = resolve<GetQuiltSettings>(
      session->module, "get_default_quilt_settings");
  session->getViewCone = resolve<GetViewCone>(session->module, "get_viewcone");
  session->getDisplayForWindow = resolve<GetDisplayForWindow>(
      session->module, "get_display_for_window");
  session->getDeviceName = resolve<GetWideString>(session->module, "get_device_name");
  session->getDeviceSerial = resolve<GetWideString>(session->module, "get_device_serial");
  session->getMaxTextureSize = resolve<GetMaxTextureSize>(
      session->module, "get_max_texture_size");
  session->presentTexture = resolve<PresentTexture>(
      session->module, "draw_interop_quilt_texture_gl");
  session->setTexture = resolve<SetTexture>(session->module, "set_interop_quilt_texture_gl");
  session->showWindow = resolve<ShowWindow>(session->module, "show_window");
  session->saveTexture = resolve<SaveTexture>(session->module, "save_texture_to_file_gl");
  return session->initialize && session->uninitialize && session->instanceWindow
      && session->getQuiltSettings && session->getViewCone && session->getDisplayForWindow
      && session->getDeviceName && session->getDeviceSerial && session->getMaxTextureSize
      && session->presentTexture && session->setTexture && session->showWindow
      && session->saveTexture;
}

Session* fromHandle(jlong handle) {
  return reinterpret_cast<Session*>(static_cast<intptr_t>(handle));
}

jstring wideString(JNIEnv* env, Session* session, GetWideString getter) {
  int count = 0;
  if (!getter(session->window, &count, nullptr) || count <= 0) return env->NewStringUTF("");
  std::vector<wchar_t> buffer(static_cast<size_t>(count) + 1, L'\0');
  if (!getter(session->window, &count, buffer.data())) return env->NewStringUTF("");
  std::string utf8;
  for (wchar_t character : buffer) {
    if (character == L'\0') break;
    appendUtf8(&utf8, static_cast<uint32_t>(character));
  }
  return env->NewStringUTF(utf8.c_str());
}

bool bridgeReportsDisplay(CGLContextObj context) {
  std::string loadError;
  void* module = loadBridgeModule(&loadError);
  if (module == nullptr) return false;
  auto initialize = resolve<InitializeBridge>(module, "initialize_bridge");
  auto uninitialize = resolve<UninitializeBridge>(module, "uninitialize_bridge");
  auto getDisplays = resolve<GetDisplays>(module, "get_displays");
  if (!initialize || !uninitialize || !getDisplays) {
    dlclose(module);
    return false;
  }
  bool connected = false;
  runOnAppKitThread(context, [&] {
    if (initialize("Processing2Hologram diagnostics")) {
      int count = 0;
      connected = getDisplays(&count, nullptr) && count > 0;
      uninitialize();
    }
  });
  dlclose(module);
  return connected;
}

}  // namespace

extern "C" JNIEXPORT jboolean JNICALL
Java_processing2hologram_internal_NativeBridge_isLookingGlassDisplayConnected(
    JNIEnv*, jclass) {
  std::lock_guard<std::mutex> lock(bridgeMutex);
  return bridgeReportsDisplay(CGLGetCurrentContext()) ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jlong JNICALL
Java_processing2hologram_internal_NativeBridge_open(
    JNIEnv* env, jclass, jstring applicationName, jlong displayIndex) {
  CglContextGuard contextGuard;
  if (!contextGuard.available()) {
    throwJava(env, "java/lang/IllegalStateException",
        "Bridge OpenGL initialization requires Processing's current P3D context");
    return 0;
  }

  auto* session = new Session();
  std::string loadError;
  session->module = loadBridgeModule(&loadError);
  if (session->module == nullptr) {
    delete session;
    throwJava(env, "java/lang/UnsatisfiedLinkError",
        "Looking Glass Bridge SDK was not found. Install Looking Glass Bridge or set "
        "LOOKING_GLASS_BRIDGE_LIBRARY. " + loadError);
    return 0;
  }
  if (!resolveAll(session)) {
    dlclose(session->module);
    delete session;
    throwJava(env, "java/lang/UnsatisfiedLinkError",
        "The installed Looking Glass Bridge does not expose the required native API");
    return 0;
  }

  std::string name = javaString(env, applicationName);
  enum class OpenResult { Pending, Opened, InitializationFailed, WindowFailed };
  OpenResult result = OpenResult::Pending;
  {
    std::lock_guard<std::mutex> lock(bridgeMutex);
    bool dispatched = runOnAppKitThread(CGLGetCurrentContext(), [&] {
      if (bridgeReferenceCount == 0 && !session->initialize(name.c_str())) {
        result = OpenResult::InitializationFailed;
        return;
      }
      ++bridgeReferenceCount;
      std::vector<NSWindow*> previousWindows = bridgeWindows();
      if (!session->instanceWindow(
              &session->window, static_cast<unsigned long>(displayIndex))) {
        --bridgeReferenceCount;
        if (bridgeReferenceCount == 0) session->uninitialize();
        result = OpenResult::WindowFailed;
        return;
      }
      session->nativeWindow = findNewBridgeWindow(previousWindows);
      result = OpenResult::Opened;
    });
    if (!dispatched) {
      if (result == OpenResult::Opened) {
        --bridgeReferenceCount;
        if (bridgeReferenceCount == 0) {
          runOnAppKitThread(nullptr, [&] { session->uninitialize(); });
        }
      }
      result = OpenResult::WindowFailed;
    }
  }
  if (result != OpenResult::Opened) {
    dlclose(session->module);
    delete session;
    if (result == OpenResult::InitializationFailed) {
      throwJava(env, "java/lang/IllegalStateException",
          "Looking Glass Bridge initialization failed. Make sure Bridge is running.");
    } else {
      throwJava(env, "java/lang/IllegalStateException",
          "Looking Glass Bridge could not create its macOS display window on the AppKit thread");
    }
    return 0;
  }
  return static_cast<jlong>(reinterpret_cast<intptr_t>(session));
}

extern "C" JNIEXPORT void JNICALL
Java_processing2hologram_internal_NativeBridge_close(JNIEnv*, jclass, jlong handle) {
  Session* session = fromHandle(handle);
  if (session == nullptr) return;
  {
    std::lock_guard<std::mutex> lock(bridgeMutex);
    if (bridgeReferenceCount > 0) {
      --bridgeReferenceCount;
      if (bridgeReferenceCount == 0) {
        runOnAppKitThread(CGLGetCurrentContext(), [&] { session->uninitialize(); });
      }
    }
  }
  dlclose(session->module);
  delete session;
}

extern "C" JNIEXPORT jintArray JNICALL
Java_processing2hologram_internal_NativeBridge_getQuiltSettings(
    JNIEnv* env, jclass, jlong handle) {
  Session* session = fromHandle(handle);
  float aspect = 0.0f;
  int width = 0, height = 0, columns = 0, rows = 0;
  if (!session->getQuiltSettings(
          session->window, &aspect, &width, &height, &columns, &rows)) {
    throwJava(env, "java/lang/IllegalStateException", "Bridge could not provide quilt settings");
    return nullptr;
  }
  jint values[] = {
      width, height, columns, rows, static_cast<jint>(std::bit_cast<uint32_t>(aspect))};
  jintArray result = env->NewIntArray(5);
  if (result != nullptr) env->SetIntArrayRegion(result, 0, 5, values);
  return result;
}

extern "C" JNIEXPORT jfloat JNICALL
Java_processing2hologram_internal_NativeBridge_getViewCone(
    JNIEnv* env, jclass, jlong handle) {
  Session* session = fromHandle(handle);
  float value = 0.0f;
  if (!session->getViewCone(session->window, &value)) {
    throwJava(env, "java/lang/IllegalStateException", "Bridge could not provide the view cone");
  }
  return value;
}

extern "C" JNIEXPORT jlong JNICALL
Java_processing2hologram_internal_NativeBridge_getDisplayIndex(
    JNIEnv* env, jclass, jlong handle) {
  Session* session = fromHandle(handle);
  unsigned long value = 0;
  if (!session->getDisplayForWindow(session->window, &value)) {
    throwJava(env, "java/lang/IllegalStateException", "Bridge could not provide the display index");
  }
  return static_cast<jlong>(value);
}

extern "C" JNIEXPORT jstring JNICALL
Java_processing2hologram_internal_NativeBridge_getDeviceName(
    JNIEnv* env, jclass, jlong handle) {
  Session* session = fromHandle(handle);
  return wideString(env, session, session->getDeviceName);
}

extern "C" JNIEXPORT jstring JNICALL
Java_processing2hologram_internal_NativeBridge_getDeviceSerial(
    JNIEnv* env, jclass, jlong handle) {
  Session* session = fromHandle(handle);
  return wideString(env, session, session->getDeviceSerial);
}

extern "C" JNIEXPORT jint JNICALL
Java_processing2hologram_internal_NativeBridge_getMaxTextureSize(
    JNIEnv* env, jclass, jlong handle) {
  Session* session = fromHandle(handle);
  unsigned long value = 0;
  if (!session->getMaxTextureSize(session->window, &value)) {
    throwJava(env, "java/lang/IllegalStateException",
        "Bridge could not provide its texture limit");
  }
  return static_cast<jint>(value);
}

extern "C" JNIEXPORT jboolean JNICALL
Java_processing2hologram_internal_NativeBridge_present(
    JNIEnv* env, jclass, jlong handle, jlong texture, jint pixelFormat,
    jint width, jint height, jint columns, jint rows, jfloat aspect, jfloat zoom) {
  Session* session = fromHandle(handle);
  CglContextGuard contextGuard;
  if (!contextGuard.available()) {
    throwJava(env, "java/lang/IllegalStateException",
        "Quilt submission requires Processing's current OpenGL context");
    return JNI_FALSE;
  }
  glFlush();
  if (!session->windowShown) {
    bool shown = false;
    if (!runOnAppKitThread(CGLGetCurrentContext(), [&] {
          shown = session->showWindow(session->window, true);
          if (shown) fitBridgeWindowToDisplay(session);
        }) || !shown) {
      return JNI_FALSE;
    }
    session->windowShown = true;
  }
  unsigned long long textureName = static_cast<unsigned long long>(texture);
  unsigned long textureWidth = static_cast<unsigned long>(width);
  unsigned long textureHeight = static_cast<unsigned long>(height);
  unsigned long textureColumns = static_cast<unsigned long>(columns);
  unsigned long textureRows = static_cast<unsigned long>(rows);
  bool changed = session->registeredTexture != textureName
      || session->registeredPixelFormat != pixelFormat
      || session->registeredWidth != textureWidth
      || session->registeredHeight != textureHeight
      || session->registeredColumns != textureColumns
      || session->registeredRows != textureRows
      || session->registeredAspect != aspect || session->registeredZoom != zoom;
  if (changed && !session->setTexture(
          session->window, textureName, pixelFormat, textureWidth, textureHeight,
          textureColumns, textureRows, aspect, zoom)) {
    return JNI_FALSE;
  }
  if (changed) {
    session->registeredTexture = textureName;
    session->registeredPixelFormat = pixelFormat;
    session->registeredWidth = textureWidth;
    session->registeredHeight = textureHeight;
    session->registeredColumns = textureColumns;
    session->registeredRows = textureRows;
    session->registeredAspect = aspect;
    session->registeredZoom = zoom;
  }
  return session->presentTexture(
      session->window, textureName, pixelFormat, textureWidth, textureHeight,
      textureColumns, textureRows, aspect, zoom) ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_processing2hologram_internal_NativeBridge_saveTexture(
    JNIEnv* env, jclass, jlong handle, jstring filename, jlong texture,
    jint pixelFormat, jint width, jint height) {
  Session* session = fromHandle(handle);
  CglContextGuard contextGuard;
  if (!contextGuard.available()) {
    throwJava(env, "java/lang/IllegalStateException",
        "Bridge texture export requires Processing's current OpenGL context");
    return JNI_FALSE;
  }
  std::string path = javaString(env, filename);
  glFlush();
  return session->saveTexture(
      session->window, path.data(), static_cast<unsigned long long>(texture), pixelFormat,
      static_cast<unsigned long>(width), static_cast<unsigned long>(height))
      ? JNI_TRUE : JNI_FALSE;
}
