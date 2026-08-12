package processing2hologram.internal;

/** Minimal JNI surface over the Looking Glass Bridge C API. */
public final class NativeBridge implements AutoCloseable {
  private long session;

  public NativeBridge(String applicationName, long displayIndex) {
    NativeLibraryLoader.load();
    if (Boolean.getBoolean("processing2hologram.offline")) {
      throw new IllegalStateException("Offline mode was explicitly requested");
    }
    if (!isDisplayConnected() && !Boolean.getBoolean("processing2hologram.forceBridge")) {
      throw new IllegalStateException(
          "Windows does not currently report a connected Looking Glass display");
    }
    session = open(applicationName, displayIndex);
    if (session == 0L) {
      throw new IllegalStateException("Looking Glass Bridge could not create a display window");
    }
  }

  /** Safe preflight that does not initialize the Looking Glass Bridge SDK. */
  public static boolean isDisplayConnected() {
    NativeLibraryLoader.load();
    return isLookingGlassDisplayConnected();
  }

  public int[] quiltSettings() {
    ensureOpen();
    return getQuiltSettings(session);
  }

  public float viewConeDegrees() {
    ensureOpen();
    return getViewCone(session);
  }

  public long displayIndex() {
    ensureOpen();
    return getDisplayIndex(session);
  }

  public String deviceName() {
    ensureOpen();
    return getDeviceName(session);
  }

  public String deviceSerial() {
    ensureOpen();
    return getDeviceSerial(session);
  }

  public int maxTextureSize() {
    ensureOpen();
    return getMaxTextureSize(session);
  }

  public void present(
      long texture, int pixelFormat, int width, int height,
      int columns, int rows, float aspect, float zoom) {
    ensureOpen();
    if (!present(session, texture, pixelFormat, width, height, columns, rows, aspect, zoom)) {
      throw new IllegalStateException("Looking Glass Bridge rejected the quilt texture");
    }
  }

  public void saveTexture(
      String filename, long texture, int pixelFormat, int width, int height) {
    ensureOpen();
    if (!saveTexture(session, filename, texture, pixelFormat, width, height)) {
      throw new IllegalStateException("Looking Glass Bridge could not read the quilt texture");
    }
  }

  @Override
  public synchronized void close() {
    if (session != 0L) {
      close(session);
      session = 0L;
    }
  }

  private void ensureOpen() {
    if (session == 0L) throw new IllegalStateException("Looking Glass Bridge session is closed");
  }

  private static native long open(String applicationName, long displayIndex);
  private static native boolean isLookingGlassDisplayConnected();
  private static native void close(long session);
  private static native int[] getQuiltSettings(long session);
  private static native float getViewCone(long session);
  private static native long getDisplayIndex(long session);
  private static native String getDeviceName(long session);
  private static native String getDeviceSerial(long session);
  private static native int getMaxTextureSize(long session);
  private static native boolean present(
      long session, long texture, int pixelFormat, int width, int height,
      int columns, int rows, float aspect, float zoom);
  private static native boolean saveTexture(
      long session, String filename, long texture, int pixelFormat, int width, int height);
}
