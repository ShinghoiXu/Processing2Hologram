package processing2hologram.internal;

import processing2hologram.DeviceInfo;
import processing2hologram.QuiltSettings;

/** Owns one Bridge display window and converts native failures to actionable Java errors. */
public final class BridgeConnection implements AutoCloseable {
  private final NativeBridge bridge;
  private final QuiltSettings quiltSettings;
  private final DeviceInfo deviceInfo;
  private final int maxTextureSize;

  public BridgeConnection(String applicationName, long displayIndex) {
    bridge = new NativeBridge(applicationName, displayIndex);
    try {
      int[] nativeSettings = bridge.quiltSettings();
      if (nativeSettings == null || nativeSettings.length != 5) {
        throw new IllegalStateException("Looking Glass Bridge returned invalid quilt settings");
      }
      float aspect = Float.intBitsToFloat(nativeSettings[4]);
      quiltSettings = new QuiltSettings(
          nativeSettings[0], nativeSettings[1], nativeSettings[2], nativeSettings[3], aspect);
      maxTextureSize = bridge.maxTextureSize();
      if (quiltSettings.width() > maxTextureSize || quiltSettings.height() > maxTextureSize) {
        throw new IllegalStateException(
            "The recommended quilt " + quiltSettings.width() + "x" + quiltSettings.height()
                + " exceeds Bridge's maximum texture size " + maxTextureSize);
      }
      deviceInfo = new DeviceInfo(
          bridge.displayIndex(), bridge.deviceName(), bridge.deviceSerial(), bridge.viewConeDegrees());
    } catch (RuntimeException | Error failure) {
      bridge.close();
      throw failure;
    }
  }

  public QuiltSettings quiltSettings() {
    return quiltSettings;
  }

  public DeviceInfo deviceInfo() {
    return deviceInfo;
  }

  public int maxTextureSize() {
    return maxTextureSize;
  }

  public void present(long textureName, int pixelFormat, float zoom) {
    bridge.present(
        textureName, pixelFormat,
        quiltSettings.width(), quiltSettings.height(),
        quiltSettings.columns(), quiltSettings.rows(),
        quiltSettings.viewAspect(), zoom);
  }

  public void saveTexture(String filename, long textureName, int pixelFormat) {
    bridge.saveTexture(
        filename, textureName, pixelFormat, quiltSettings.width(), quiltSettings.height());
  }

  @Override
  public void close() {
    bridge.close();
  }
}
