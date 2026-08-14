package processing2hologram;

import java.util.Objects;
import processing.core.PApplet;
import processing.core.PConstants;
import processing.core.PGraphics;
import processing.opengl.PGraphics3D;
import processing.opengl.PGraphicsOpenGL;
import processing.opengl.Texture;
import processing2hologram.internal.BridgeConnection;

/**
 * Real-time multiview renderer for Processing and Looking Glass displays.
 *
 * <p>Update scene state once, then pass a side-effect-free scene drawing callback to
 * {@link #render(SceneRenderer)}. The callback is repeated for every horizontal view.</p>
 */
public final class LookingGlass implements AutoCloseable {
  public static final String VERSION = "0.1.3";
  public static final long FIRST_DISPLAY = 0xffff_ffffL;

  private static final float PORTRAIT_VIEW_CONE_DEGREES = 40f;

  private final PApplet parent;
  private final PGraphicsOpenGL primaryGraphics;
  private final BridgeConnection bridge;
  private final QuiltSettings quiltSettings;
  private final DeviceInfo deviceInfo;
  private final PGraphics3D viewBuffer;
  private final PGraphicsOpenGL quiltBuffer;
  private final PGraphicsOpenGL bridgeBuffer;
  private final PGraphics previewBuffer;
  private final HolographicCamera camera;
  private final String startupMessage;

  private float zoom = 1f;
  private boolean closed;
  private boolean presentingEnabled = true;
  private String lastPresentationError;

  /** Connects to the first available Looking Glass, falling back to a Portrait quilt preview. */
  public LookingGlass(PApplet parent) {
    this(parent, FIRST_DISPLAY);
  }

  /** Connects to a Bridge display index, falling back to a Portrait quilt preview if unavailable. */
  public LookingGlass(PApplet parent, long displayIndex) {
    this.parent = Objects.requireNonNull(parent, "parent");
    if (!(parent.g instanceof PGraphicsOpenGL) || !parent.g.is3D()) {
      throw new IllegalArgumentException(
          "Processing2Hologram requires a P3D sketch. Use size(width, height, P3D) in setup().");
    }
    primaryGraphics = (PGraphicsOpenGL) parent.g;

    BridgeConnection openedBridge = null;
    QuiltSettings settings = QuiltSettings.portrait();
    DeviceInfo info = null;
    String message;
    try {
      openedBridge = new BridgeConnection("Processing2Hologram", displayIndex);
      settings = openedBridge.quiltSettings();
      info = openedBridge.deviceInfo();
      message = "Connected to " + info + " using quilt " + settings;
    } catch (RuntimeException | LinkageError failure) {
      message = "Looking Glass output unavailable; rendering Portrait quilt preview only. "
          + rootMessage(failure);
    }
    bridge = openedBridge;
    quiltSettings = settings;
    deviceInfo = info;
    startupMessage = message;

    viewBuffer = (PGraphics3D) parent.createGraphics(
        quiltSettings.viewWidth(), quiltSettings.viewHeight(), PConstants.P3D);
    quiltBuffer = (PGraphicsOpenGL) parent.createGraphics(
        quiltSettings.width(), quiltSettings.height(), PConstants.P2D);
    bridgeBuffer = bridge == null ? null : (PGraphicsOpenGL) parent.createGraphics(
        quiltSettings.width(), quiltSettings.height(), PConstants.P2D);
    previewBuffer = parent.createGraphics(
        quiltSettings.viewWidth(), quiltSettings.viewHeight(), PConstants.P2D);
    viewBuffer.noSmooth();
    quiltBuffer.noSmooth();
    if (bridgeBuffer != null) bridgeBuffer.noSmooth();
    previewBuffer.noSmooth();
    camera = new HolographicCamera(quiltSettings.viewWidth(), quiltSettings.viewHeight());

    clearBuffer(quiltBuffer);
    if (bridgeBuffer != null) clearBuffer(bridgeBuffer);
    clearBuffer(previewBuffer);
    parent.registerMethod("dispose", this);
    PApplet.println("Processing2Hologram " + VERSION + ": " + startupMessage);
  }

  /** Renders one immutable scene snapshot into all quilt views and presents it to Bridge. */
  public void render(SceneRenderer scene) {
    ensureOpen();
    Objects.requireNonNull(scene, "scene");

    clearBuffer(quiltBuffer);
    int viewCount = quiltSettings.viewCount();
    int previewIndex = (viewCount - 1) / 2;
    float viewCone = deviceInfo == null
        ? PORTRAIT_VIEW_CONE_DEGREES
        : deviceInfo.viewConeDegrees();
    if (!Float.isFinite(viewCone) || viewCone <= 0f) viewCone = PORTRAIT_VIEW_CONE_DEGREES;

    for (int viewIndex = 0; viewIndex < viewCount; viewIndex++) {
      renderView(scene, viewIndex, viewCount, viewCone);
      if (viewIndex == previewIndex) copyViewToPreview();
      copyViewToQuilt(viewIndex);
    }

    if (bridge != null && presentingEnabled) {
      prepareBridgeBuffer();
      presentQuilt();
    }
  }

  public HolographicCamera camera() {
    return camera;
  }

  /** Returns the center-nearest view for display in the normal Processing window. */
  public PGraphics preview() {
    return previewBuffer;
  }

  /** Returns the complete quilt for debugging or saving. */
  public PGraphics quilt() {
    return quiltBuffer;
  }

  public QuiltSettings quiltSettings() {
    return quiltSettings;
  }

  public DeviceInfo device() {
    return deviceInfo;
  }

  public boolean isConnected() {
    return bridge != null && presentingEnabled;
  }

  public String status() {
    if (lastPresentationError != null) return lastPresentationError;
    return startupMessage;
  }

  /** Bridge-side final zoom. A value of one preserves the rendered quilt framing. */
  public LookingGlass zoom(float zoom) {
    if (!Float.isFinite(zoom) || zoom <= 0f) {
      throw new IllegalArgumentException("Zoom must be positive and finite");
    }
    this.zoom = zoom;
    return this;
  }

  /** Saves the latest quilt with the standard Looking Glass filename metadata. */
  public void saveQuilt(String baseName) {
    ensureOpen();
    if (baseName == null || baseName.isBlank()) {
      throw new IllegalArgumentException("Quilt base name cannot be blank");
    }
    quiltBuffer.save(baseName + "_qs" + quiltSettings.columns() + "x"
        + quiltSettings.rows() + "a" + quiltSettings.viewAspect() + ".png");
  }

  /**
   * Asks Bridge to read the current shared OpenGL quilt and save it as an image.
   * This is intended for diagnosing GPU texture-sharing problems on connected hardware.
   */
  public void saveBridgeQuilt(String filename) {
    ensureOpen();
    if (bridge == null) {
      throw new IllegalStateException("A Looking Glass must be connected to save through Bridge");
    }
    if (filename == null || filename.isBlank()) {
      throw new IllegalArgumentException("Bridge quilt filename cannot be blank");
    }
    Texture texture = bridgeBuffer.getTexture();
    if (texture == null || !texture.available()) {
      throw new IllegalStateException("Processing did not expose the quilt OpenGL texture");
    }
    primaryGraphics.beginPGL();
    try {
      bridge.saveTexture(
          filename, Integer.toUnsignedLong(texture.glName), texture.glFormat,
          texture.width, texture.height);
    } finally {
      primaryGraphics.endPGL();
    }
  }

  /** Processing lifecycle callback. */
  public void dispose() {
    close();
  }

  @Override
  public void close() {
    if (closed) return;
    closed = true;
    parent.unregisterMethod("dispose", this);
    if (bridge != null) bridge.close();
    viewBuffer.dispose();
    quiltBuffer.dispose();
    if (bridgeBuffer != null) bridgeBuffer.dispose();
    previewBuffer.dispose();
  }

  private void renderView(SceneRenderer scene, int viewIndex, int viewCount, float viewCone) {
    viewBuffer.beginDraw();
    try {
      viewBuffer.resetMatrix();
      camera.apply(viewBuffer, viewIndex, viewCount, quiltSettings.viewAspect(), viewCone);
      scene.draw(viewBuffer);
    } finally {
      viewBuffer.endDraw();
    }
  }

  private void copyViewToPreview() {
    previewBuffer.beginDraw();
    previewBuffer.background(0);
    previewBuffer.image(viewBuffer, 0, 0);
    previewBuffer.endDraw();
  }

  private void copyViewToQuilt(int viewIndex) {
    int column = viewIndex % quiltSettings.columns();
    int rowFromBottom = viewIndex / quiltSettings.columns();
    int x = column * quiltSettings.viewWidth();
    int y = quiltSettings.height() - (rowFromBottom + 1) * quiltSettings.viewHeight();

    quiltBuffer.beginDraw();
    quiltBuffer.image(viewBuffer, x, y);
    quiltBuffer.endDraw();
  }

  private void presentQuilt() {
    try {
      Texture texture = bridgeBuffer.getTexture();
      if (texture == null || !texture.available()) {
        throw new IllegalStateException("Processing did not expose the quilt OpenGL texture");
      }
      // Keep the Processing OpenGL context current while Bridge registers/draws the shared texture.
      primaryGraphics.beginPGL();
      try {
        bridge.present(
            Integer.toUnsignedLong(texture.glName), texture.glFormat,
            texture.width, texture.height, zoom);
      } finally {
        primaryGraphics.endPGL();
      }
    } catch (RuntimeException | LinkageError failure) {
      presentingEnabled = false;
      lastPresentationError = "Looking Glass presentation stopped: " + rootMessage(failure)
          + ". Quilt preview remains available.";
      PApplet.println("Processing2Hologram: " + lastPresentationError);
    }
  }

  private void prepareBridgeBuffer() {
    bridgeBuffer.beginDraw();
    try {
      // Processing's offscreen OpenGL textures are vertically inverted. Pre-flip the
      // logical quilt so Bridge's raw GL texture sampling sees the standard orientation.
      bridgeBuffer.background(0);
      bridgeBuffer.pushMatrix();
      bridgeBuffer.translate(0, bridgeBuffer.height);
      bridgeBuffer.scale(1, -1);
      bridgeBuffer.image(quiltBuffer, 0, 0);
      bridgeBuffer.popMatrix();
    } finally {
      bridgeBuffer.endDraw();
    }
  }

  private static void clearBuffer(PGraphics buffer) {
    buffer.beginDraw();
    buffer.background(0);
    buffer.endDraw();
  }

  private void ensureOpen() {
    if (closed) throw new IllegalStateException("LookingGlass renderer is closed");
  }

  private static String rootMessage(Throwable failure) {
    Throwable root = failure;
    while (root.getCause() != null) root = root.getCause();
    String message = root.getMessage();
    return message == null || message.isBlank() ? root.getClass().getSimpleName() : message;
  }
}
