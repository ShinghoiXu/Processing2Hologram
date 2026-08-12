#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <gl/GL.h>
#include <jni.h>

#include <bit>
#include <algorithm>
#include <cwctype>
#include <cstdint>
#include <iterator>
#include <string>
#include <vector>

namespace {

using WindowHandle = unsigned long;

using InitializeBridge = bool(__cdecl*)(const wchar_t*);
using UninitializeBridge = bool(__cdecl*)();
using InstanceWindowGL = bool(__cdecl*)(WindowHandle*, unsigned long);
using GetQuiltSettings = bool(__cdecl*)(WindowHandle, float*, int*, int*, int*, int*);
using GetViewCone = bool(__cdecl*)(WindowHandle, float*);
using GetDisplayForWindow = bool(__cdecl*)(WindowHandle, unsigned long*);
using GetWideString = bool(__cdecl*)(WindowHandle, int*, wchar_t*);
using GetMaxTextureSize = bool(__cdecl*)(WindowHandle, unsigned long*);
using PresentTexture = bool(__cdecl*)(
    WindowHandle, unsigned long long, int, unsigned long, unsigned long,
    unsigned long, unsigned long, float, float);
using SetTexture = bool(__cdecl*)(
    WindowHandle, unsigned long long, int, unsigned long, unsigned long,
    unsigned long, unsigned long, float, float);
using ShowWindow = bool(__cdecl*)(WindowHandle, bool);
using SetWindowPolling = void(__cdecl*)(WindowHandle, bool);
using SaveTexture = bool(__cdecl*)(
    WindowHandle, wchar_t*, unsigned long long, int, unsigned long, unsigned long);

struct Session {
  HMODULE module = nullptr;
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
  SetWindowPolling setWindowPolling = nullptr;
  SaveTexture saveTexture = nullptr;
  HGLRC applicationContext = nullptr;
  HWND bridgeHostWindow = nullptr;
  HGLRC bridgeContext = nullptr;
  HDC bridgeDeviceContext = nullptr;
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

SRWLOCK bridgeLock = SRWLOCK_INIT;
int bridgeReferenceCount = 0;

class ExclusiveBridgeLock {
 public:
  ExclusiveBridgeLock() { AcquireSRWLockExclusive(&bridgeLock); }
  ~ExclusiveBridgeLock() { ReleaseSRWLockExclusive(&bridgeLock); }
  ExclusiveBridgeLock(const ExclusiveBridgeLock&) = delete;
  ExclusiveBridgeLock& operator=(const ExclusiveBridgeLock&) = delete;
};

class WglContextGuard {
 public:
  WglContextGuard()
      : context_(wglGetCurrentContext()), deviceContext_(wglGetCurrentDC()) {}

  ~WglContextGuard() {
    if (context_ != nullptr && deviceContext_ != nullptr
        && (wglGetCurrentContext() != context_ || wglGetCurrentDC() != deviceContext_)) {
      wglMakeCurrent(deviceContext_, context_);
    }
  }

  HGLRC context() const { return context_; }
  HDC deviceContext() const { return deviceContext_; }
  bool available() const { return context_ != nullptr && deviceContext_ != nullptr; }

 private:
  HGLRC context_;
  HDC deviceContext_;
};

LRESULT CALLBACK bridgeHostWindowProc(
    HWND window, UINT message, WPARAM wordParameter, LPARAM longParameter) {
  return DefWindowProcW(window, message, wordParameter, longParameter);
}

bool createSharedBridgeContext(Session* session, std::string* error) {
  static constexpr wchar_t className[] = L"Processing2HologramBridgeGLHost";
  HINSTANCE processInstance = GetModuleHandleW(nullptr);
  WNDCLASSW windowClass = {};
  windowClass.style = CS_OWNDC;
  windowClass.lpfnWndProc = bridgeHostWindowProc;
  windowClass.hInstance = processInstance;
  windowClass.lpszClassName = className;
  if (!RegisterClassW(&windowClass) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
    *error = "Could not register the private Bridge OpenGL window class";
    return false;
  }
  session->bridgeHostWindow = CreateWindowExW(
      0, className, L"Processing2Hologram Bridge GL host", WS_POPUP,
      0, 0, 64, 64, nullptr, nullptr, processInstance, nullptr);
  if (session->bridgeHostWindow == nullptr) {
    *error = "Could not create the private Bridge OpenGL host window";
    return false;
  }
  session->bridgeDeviceContext = GetDC(session->bridgeHostWindow);
  PIXELFORMATDESCRIPTOR descriptor = {};
  descriptor.nSize = sizeof(descriptor);
  descriptor.nVersion = 1;
  descriptor.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
  descriptor.iPixelType = PFD_TYPE_RGBA;
  descriptor.cColorBits = 32;
  descriptor.cDepthBits = 24;
  int pixelFormat = ChoosePixelFormat(session->bridgeDeviceContext, &descriptor);
  if (pixelFormat == 0
      || !SetPixelFormat(session->bridgeDeviceContext, pixelFormat, &descriptor)) {
    *error = "Could not set a double-buffered pixel format for the private Bridge context";
    return false;
  }
  session->bridgeContext = wglCreateContext(session->bridgeDeviceContext);
  if (session->bridgeContext == nullptr) {
    *error = "Could not create the private Bridge OpenGL compatibility context";
    return false;
  }
  if (!wglShareLists(session->applicationContext, session->bridgeContext)) {
    *error = "Could not share OpenGL textures between Processing and Bridge";
    return false;
  }
  if (!wglMakeCurrent(session->bridgeDeviceContext, session->bridgeContext)) {
    *error = "Could not activate the private Bridge OpenGL compatibility context";
    return false;
  }
  return true;
}

void destroySharedBridgeContext(Session* session) {
  if (wglGetCurrentContext() == session->bridgeContext) wglMakeCurrent(nullptr, nullptr);
  if (session->bridgeContext != nullptr) {
    wglDeleteContext(session->bridgeContext);
    session->bridgeContext = nullptr;
  }
  if (session->bridgeDeviceContext != nullptr && session->bridgeHostWindow != nullptr) {
    ReleaseDC(session->bridgeHostWindow, session->bridgeDeviceContext);
    session->bridgeDeviceContext = nullptr;
  }
  if (session->bridgeHostWindow != nullptr) {
    DestroyWindow(session->bridgeHostWindow);
    session->bridgeHostWindow = nullptr;
  }
}

bool activateBridgeContext(Session* session) {
  return session->bridgeContext != nullptr && session->bridgeDeviceContext != nullptr
      && wglMakeCurrent(session->bridgeDeviceContext, session->bridgeContext) == TRUE;
}

void pumpBridgeWindowMessages() {
  MSG message = {};
  while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
    TranslateMessage(&message);
    DispatchMessageW(&message);
  }
}

void throwJava(JNIEnv* env, const char* className, const std::string& message) {
  jclass exceptionClass = env->FindClass(className);
  if (exceptionClass != nullptr) env->ThrowNew(exceptionClass, message.c_str());
}

std::wstring javaString(JNIEnv* env, jstring value) {
  if (value == nullptr) return L"Processing2Hologram";
  const jchar* chars = env->GetStringChars(value, nullptr);
  if (chars == nullptr) return L"";
  jsize length = env->GetStringLength(value);
  std::wstring result(reinterpret_cast<const wchar_t*>(chars), static_cast<size_t>(length));
  env->ReleaseStringChars(value, chars);
  return result;
}

std::string windowsErrorMessage(DWORD error) {
  wchar_t* message = nullptr;
  DWORD length = FormatMessageW(
      FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
      nullptr, error, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
      reinterpret_cast<wchar_t*>(&message), 0, nullptr);
  if (length == 0 || message == nullptr) return "Windows error " + std::to_string(error);
  int utf8Length = WideCharToMultiByte(CP_UTF8, 0, message, length, nullptr, 0, nullptr, nullptr);
  std::string result(static_cast<size_t>(utf8Length), '\0');
  WideCharToMultiByte(CP_UTF8, 0, message, length, result.data(), utf8Length, nullptr, nullptr);
  LocalFree(message);
  while (!result.empty() && (result.back() == '\r' || result.back() == '\n')) result.pop_back();
  return result;
}

HMODULE loadBridgeModule() {
  wchar_t overridePath[32768] = {};
  DWORD overrideLength = GetEnvironmentVariableW(
      L"LOOKING_GLASS_BRIDGE_DLL", overridePath, static_cast<DWORD>(std::size(overridePath)));
  if (overrideLength > 0 && overrideLength < std::size(overridePath)) {
    return LoadLibraryExW(overridePath, nullptr, LOAD_WITH_ALTERED_SEARCH_PATH);
  }

  HMODULE moduleOnPath = LoadLibraryW(L"bridge_inproc.dll");
  if (moduleOnPath != nullptr) return moduleOnPath;

  HMODULE unversioned = LoadLibraryExW(
      L"C:\\Program Files\\Looking Glass\\Looking Glass Bridge\\bridge_inproc.dll",
      nullptr, LOAD_WITH_ALTERED_SEARCH_PATH);
  if (unversioned != nullptr) return unversioned;

  WIN32_FIND_DATAW findData = {};
  HANDLE search = FindFirstFileW(L"C:\\Program Files\\Looking Glass\\Looking Glass Bridge *", &findData);
  if (search == INVALID_HANDLE_VALUE) return nullptr;

  std::vector<std::wstring> candidates;
  do {
    if ((findData.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
      candidates.emplace_back(
          L"C:\\Program Files\\Looking Glass\\" + std::wstring(findData.cFileName)
              + L"\\bridge_inproc.dll");
    }
  } while (FindNextFileW(search, &findData));
  FindClose(search);

  std::sort(candidates.begin(), candidates.end());
  for (auto iterator = candidates.rbegin(); iterator != candidates.rend(); ++iterator) {
    HMODULE module = LoadLibraryExW(
        iterator->c_str(), nullptr, LOAD_WITH_ALTERED_SEARCH_PATH);
    if (module != nullptr) return module;
  }
  return nullptr;
}

template <typename Function>
Function resolve(Session* session, const char* name) {
  return reinterpret_cast<Function>(GetProcAddress(session->module, name));
}

bool resolveAll(Session* session) {
  session->initialize = resolve<InitializeBridge>(session, "initialize_bridge");
  session->uninitialize = resolve<UninitializeBridge>(session, "uninitialize_bridge");
  session->instanceWindow = resolve<InstanceWindowGL>(session, "instance_window_gl");
  session->getQuiltSettings = resolve<GetQuiltSettings>(session, "get_default_quilt_settings");
  session->getViewCone = resolve<GetViewCone>(session, "get_viewcone");
  session->getDisplayForWindow = resolve<GetDisplayForWindow>(session, "get_display_for_window");
  session->getDeviceName = resolve<GetWideString>(session, "get_device_name");
  session->getDeviceSerial = resolve<GetWideString>(session, "get_device_serial");
  session->getMaxTextureSize = resolve<GetMaxTextureSize>(session, "get_max_texture_size");
  session->presentTexture = resolve<PresentTexture>(session, "draw_interop_quilt_texture_gl");
  session->setTexture = resolve<SetTexture>(session, "set_interop_quilt_texture_gl");
  session->showWindow = resolve<ShowWindow>(session, "show_window");
  session->setWindowPolling = resolve<SetWindowPolling>(session, "set_window_polling");
  session->saveTexture = resolve<SaveTexture>(session, "save_texture_to_file_gl");
  return session->initialize && session->uninitialize && session->instanceWindow
      && session->getQuiltSettings && session->getViewCone && session->getDisplayForWindow
      && session->getDeviceName && session->getDeviceSerial && session->getMaxTextureSize
      && session->presentTexture && session->setTexture
      && session->showWindow && session->setWindowPolling && session->saveTexture;
}

Session* fromHandle(jlong handle) {
  return reinterpret_cast<Session*>(static_cast<intptr_t>(handle));
}

jstring wideString(JNIEnv* env, Session* session, GetWideString getter) {
  int count = 0;
  if (!getter(session->window, &count, nullptr) || count <= 0) return env->NewStringUTF("");
  std::vector<wchar_t> buffer(static_cast<size_t>(count) + 1, L'\0');
  if (!getter(session->window, &count, buffer.data())) return env->NewStringUTF("");
  size_t length = 0;
  while (length < buffer.size() && buffer[length] != L'\0') ++length;
  return env->NewString(reinterpret_cast<const jchar*>(buffer.data()), static_cast<jsize>(length));
}

bool containsLookingGlassName(const wchar_t* text) {
  if (text == nullptr || text[0] == L'\0') return false;
  std::wstring upper(text);
  std::transform(upper.begin(), upper.end(), upper.begin(), [](wchar_t character) {
    return static_cast<wchar_t>(towupper(character));
  });
  return upper.find(L"LOOKING GLASS") != std::wstring::npos
      || upper.find(L"LOOKINGGLASS") != std::wstring::npos
      || upper.find(L"LKG") != std::wstring::npos;
}

bool isLookingGlassDisplayConnected() {
  DISPLAY_DEVICEW adapter = {};
  adapter.cb = sizeof(adapter);
  for (DWORD adapterIndex = 0;
       EnumDisplayDevicesW(nullptr, adapterIndex, &adapter, 0);
       ++adapterIndex) {
    if (containsLookingGlassName(adapter.DeviceString)
        || containsLookingGlassName(adapter.DeviceID)) {
      return true;
    }

    DISPLAY_DEVICEW monitor = {};
    monitor.cb = sizeof(monitor);
    for (DWORD monitorIndex = 0;
         EnumDisplayDevicesW(adapter.DeviceName, monitorIndex, &monitor, 0);
         ++monitorIndex) {
      if (containsLookingGlassName(monitor.DeviceString)
          || containsLookingGlassName(monitor.DeviceID)) {
        return true;
      }
      monitor = {};
      monitor.cb = sizeof(monitor);
    }
    adapter = {};
    adapter.cb = sizeof(adapter);
  }
  return false;
}

}  // namespace

extern "C" JNIEXPORT jboolean JNICALL
Java_processing2hologram_internal_NativeBridge_isLookingGlassDisplayConnected(
    JNIEnv*, jclass) {
  return isLookingGlassDisplayConnected() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jlong JNICALL
Java_processing2hologram_internal_NativeBridge_open(
    JNIEnv* env, jclass, jstring applicationName, jlong displayIndex) {
  WglContextGuard contextGuard;
  if (!contextGuard.available()) {
    throwJava(env, "java/lang/IllegalStateException",
        "Bridge OpenGL initialization requires Processing's current P3D context");
    return 0;
  }

  auto* session = new Session();
  session->applicationContext = contextGuard.context();
  session->module = loadBridgeModule();
  if (session->module == nullptr) {
    DWORD error = GetLastError();
    delete session;
    throwJava(env, "java/lang/UnsatisfiedLinkError",
        "Looking Glass Bridge SDK was not found. Install Looking Glass Bridge or set "
        "LOOKING_GLASS_BRIDGE_DLL. " + windowsErrorMessage(error));
    return 0;
  }
  if (!resolveAll(session)) {
    FreeLibrary(session->module);
    delete session;
    throwJava(env, "java/lang/UnsatisfiedLinkError",
        "The installed Looking Glass Bridge does not expose the required native API");
    return 0;
  }
  std::string contextError;
  if (!createSharedBridgeContext(session, &contextError)) {
    destroySharedBridgeContext(session);
    FreeLibrary(session->module);
    delete session;
    throwJava(env, "java/lang/IllegalStateException", contextError);
    return 0;
  }
  ExclusiveBridgeLock lock;
  if (bridgeReferenceCount == 0) {
    std::wstring name = javaString(env, applicationName);
    if (!session->initialize(name.c_str())) {
      destroySharedBridgeContext(session);
      FreeLibrary(session->module);
      delete session;
      throwJava(env, "java/lang/IllegalStateException",
          "Looking Glass Bridge initialization failed. Make sure Bridge is running.");
      return 0;
    }
  }
  ++bridgeReferenceCount;

  unsigned long display = static_cast<unsigned long>(displayIndex);
  if (!session->instanceWindow(&session->window, display)) {
    --bridgeReferenceCount;
    if (bridgeReferenceCount == 0) session->uninitialize();
    destroySharedBridgeContext(session);
    FreeLibrary(session->module);
    delete session;
    throwJava(env, "java/lang/IllegalStateException",
        "No usable Looking Glass display was found by Bridge");
    return 0;
  }
  // The Processing animation thread owns this native window. We pump its Win32
  // messages explicitly in present(), matching Bridge's native OpenGL samples.
  session->setWindowPolling(session->window, false);
  return static_cast<jlong>(reinterpret_cast<intptr_t>(session));
}

extern "C" JNIEXPORT void JNICALL
Java_processing2hologram_internal_NativeBridge_close(JNIEnv*, jclass, jlong handle) {
  Session* session = fromHandle(handle);
  if (session == nullptr) return;
  ExclusiveBridgeLock lock;
  if (bridgeReferenceCount > 0) {
    --bridgeReferenceCount;
    if (bridgeReferenceCount == 0) session->uninitialize();
  }
  destroySharedBridgeContext(session);
  FreeLibrary(session->module);
  delete session;
}

extern "C" JNIEXPORT jintArray JNICALL
Java_processing2hologram_internal_NativeBridge_getQuiltSettings(JNIEnv* env, jclass, jlong handle) {
  Session* session = fromHandle(handle);
  float aspect = 0.0f;
  int width = 0, height = 0, columns = 0, rows = 0;
  if (!session->getQuiltSettings(
          session->window, &aspect, &width, &height, &columns, &rows)) {
    throwJava(env, "java/lang/IllegalStateException", "Bridge could not provide quilt settings");
    return nullptr;
  }
  jint values[] = {width, height, columns, rows, static_cast<jint>(std::bit_cast<uint32_t>(aspect))};
  jintArray result = env->NewIntArray(5);
  if (result != nullptr) env->SetIntArrayRegion(result, 0, 5, values);
  return result;
}

extern "C" JNIEXPORT jfloat JNICALL
Java_processing2hologram_internal_NativeBridge_getViewCone(JNIEnv* env, jclass, jlong handle) {
  Session* session = fromHandle(handle);
  float value = 0.0f;
  if (!session->getViewCone(session->window, &value)) {
    throwJava(env, "java/lang/IllegalStateException", "Bridge could not provide the view cone");
  }
  return value;
}

extern "C" JNIEXPORT jlong JNICALL
Java_processing2hologram_internal_NativeBridge_getDisplayIndex(JNIEnv* env, jclass, jlong handle) {
  Session* session = fromHandle(handle);
  unsigned long value = 0;
  if (!session->getDisplayForWindow(session->window, &value)) {
    throwJava(env, "java/lang/IllegalStateException", "Bridge could not provide the display index");
  }
  return static_cast<jlong>(value);
}

extern "C" JNIEXPORT jstring JNICALL
Java_processing2hologram_internal_NativeBridge_getDeviceName(JNIEnv* env, jclass, jlong handle) {
  Session* session = fromHandle(handle);
  return wideString(env, session, session->getDeviceName);
}

extern "C" JNIEXPORT jstring JNICALL
Java_processing2hologram_internal_NativeBridge_getDeviceSerial(JNIEnv* env, jclass, jlong handle) {
  Session* session = fromHandle(handle);
  return wideString(env, session, session->getDeviceSerial);
}

extern "C" JNIEXPORT jint JNICALL
Java_processing2hologram_internal_NativeBridge_getMaxTextureSize(JNIEnv* env, jclass, jlong handle) {
  Session* session = fromHandle(handle);
  unsigned long value = 0;
  if (!session->getMaxTextureSize(session->window, &value)) {
    throwJava(env, "java/lang/IllegalStateException", "Bridge could not provide its texture limit");
  }
  return static_cast<jint>(value);
}

extern "C" JNIEXPORT jboolean JNICALL
Java_processing2hologram_internal_NativeBridge_present(
    JNIEnv* env, jclass, jlong handle, jlong texture, jint pixelFormat,
    jint width, jint height, jint columns, jint rows, jfloat aspect, jfloat zoom) {
  Session* session = fromHandle(handle);
  WglContextGuard contextGuard;
  if (!contextGuard.available()) {
    throwJava(env, "java/lang/IllegalStateException",
        "Quilt submission requires Processing's current OpenGL context");
    return JNI_FALSE;
  }
  // Finish producing the quilt in Processing, then run Bridge's optical pass in a
  // private legacy-compatible context. The two contexts share texture objects.
  glFlush();
  if (!activateBridgeContext(session)) {
    throwJava(env, "java/lang/IllegalStateException",
        "Could not activate Bridge's private OpenGL compatibility context");
    return JNI_FALSE;
  }
  if (!session->windowShown) {
    if (!session->showWindow(session->window, true)) return JNI_FALSE;
    session->windowShown = true;
  }
  pumpBridgeWindowMessages();
  unsigned long textureWidth = static_cast<unsigned long>(width);
  unsigned long textureHeight = static_cast<unsigned long>(height);
  unsigned long long textureName = static_cast<unsigned long long>(texture);
  unsigned long textureColumns = static_cast<unsigned long>(columns);
  unsigned long textureRows = static_cast<unsigned long>(rows);
  bool registrationChanged = session->registeredTexture != textureName
      || session->registeredPixelFormat != pixelFormat
      || session->registeredWidth != textureWidth
      || session->registeredHeight != textureHeight
      || session->registeredColumns != textureColumns
      || session->registeredRows != textureRows
      || session->registeredAspect != aspect
      || session->registeredZoom != zoom;
  if (registrationChanged) {
    if (!session->setTexture(
            session->window, textureName, pixelFormat, textureWidth, textureHeight,
            textureColumns, textureRows, aspect, zoom)) {
      return JNI_FALSE;
    }
    session->registeredTexture = textureName;
    session->registeredPixelFormat = pixelFormat;
    session->registeredWidth = textureWidth;
    session->registeredHeight = textureHeight;
    session->registeredColumns = textureColumns;
    session->registeredRows = textureRows;
    session->registeredAspect = aspect;
    session->registeredZoom = zoom;
  }
  bool presented = session->presentTexture(
      session->window, textureName, pixelFormat, textureWidth, textureHeight,
      textureColumns, textureRows, aspect, zoom);
  pumpBridgeWindowMessages();
  return presented ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_processing2hologram_internal_NativeBridge_saveTexture(
    JNIEnv* env, jclass, jlong handle, jstring filename, jlong texture,
    jint pixelFormat, jint width, jint height) {
  Session* session = fromHandle(handle);
  WglContextGuard contextGuard;
  if (!contextGuard.available()) {
    throwJava(env, "java/lang/IllegalStateException",
        "Bridge texture export requires Processing's current OpenGL context");
    return JNI_FALSE;
  }
  std::wstring path = javaString(env, filename);
  glFlush();
  if (!activateBridgeContext(session)) {
    throwJava(env, "java/lang/IllegalStateException",
        "Could not activate Bridge's private OpenGL compatibility context");
    return JNI_FALSE;
  }
  bool saved = session->saveTexture(
      session->window, path.data(), static_cast<unsigned long long>(texture), pixelFormat,
      static_cast<unsigned long>(width), static_cast<unsigned long>(height));
  return saved ? JNI_TRUE : JNI_FALSE;
}
