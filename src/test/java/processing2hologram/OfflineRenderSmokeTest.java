package processing2hologram;

import processing.core.PApplet;
import processing.core.PGraphics;
import processing.opengl.PGraphicsOpenGL;
import processing.opengl.Texture;

/** Exercises the full Processing OpenGL quilt path without requiring Looking Glass hardware. */
public final class OfflineRenderSmokeTest extends PApplet {
  private LookingGlass hologram;

  public static void main(String[] args) {
    System.setProperty("processing2hologram.offline", "true");
    PApplet.main(OfflineRenderSmokeTest.class.getName());
  }

  @Override
  public void settings() {
    size(320, 240, P3D);
  }

  @Override
  public void setup() {
    surface.setVisible(false);
    hologram = new LookingGlass(this);
  }

  @Override
  public void draw() {
    try {
      hologram.render(this::drawScene); // Initialize Processing's GPU resources.
      long started = System.nanoTime();
      hologram.render(this::drawScene);
      long elapsedMillis = (System.nanoTime() - started) / 1_000_000L;
      check(!hologram.isConnected(), "Smoke test unexpectedly opened a hardware display");
      check(hologram.preview().width == 420 && hologram.preview().height == 560,
          "Portrait preview dimensions are incorrect");
      check(hologram.quilt().width == 3360 && hologram.quilt().height == 3360,
          "Portrait quilt dimensions are incorrect");

      hologram.preview().loadPixels();
      check(containsCubeColor(hologram.preview()), "Center preview does not contain the cube");

      hologram.quilt().loadPixels();
      int coloredTileCenters = coloredTileCenters(hologram.quilt(), hologram.quiltSettings());
      check(coloredTileCenters == hologram.quiltSettings().viewCount(),
          "Only " + coloredTileCenters + " quilt tiles contain the cube at their center");

      PGraphicsOpenGL quilt = (PGraphicsOpenGL) hologram.quilt();
      Texture texture = quilt.getTexture();
      check(texture != null && texture.available(), "Quilt OpenGL texture is unavailable");
      check(texture.glFormat == 0x1908, "Bridge expects an RGBA quilt texture");
      quilt.beginPGL();
      quilt.endPGL();

      println("OfflineRenderSmokeTest: 48-view Portrait quilt rendered successfully in "
          + elapsedMillis + " ms after warmup");
      hologram.close();
      exit();
    } catch (Throwable failure) {
      failure.printStackTrace();
      if (hologram != null) hologram.close();
      System.exit(1);
    }
  }

  private void drawScene(PGraphics graphics) {
    graphics.background(15, 18, 28);
    graphics.lights();
    graphics.pushMatrix();
    graphics.translate(graphics.width * 0.5f, graphics.height * 0.5f, 0f);
    graphics.noStroke();
    graphics.fill(80, 175, 255);
    graphics.box(150);
    graphics.popMatrix();
  }

  private static boolean containsCubeColor(PGraphics graphics) {
    for (int pixel : graphics.pixels) {
      int red = pixel >> 16 & 0xff;
      int green = pixel >> 8 & 0xff;
      int blue = pixel & 0xff;
      if (blue > 80 && green > red + 20) return true;
    }
    return false;
  }

  private static int coloredTileCenters(PGraphics graphics, QuiltSettings settings) {
    int count = 0;
    for (int row = 0; row < settings.rows(); row++) {
      for (int column = 0; column < settings.columns(); column++) {
        int x = column * settings.viewWidth() + settings.viewWidth() / 2;
        int y = row * settings.viewHeight() + settings.viewHeight() / 2;
        int pixel = graphics.pixels[y * graphics.width + x];
        int red = pixel >> 16 & 0xff;
        int green = pixel >> 8 & 0xff;
        int blue = pixel & 0xff;
        if (blue > 80 && green > red + 20) count++;
      }
    }
    return count;
  }

  private static void check(boolean condition, String message) {
    if (!condition) throw new AssertionError(message);
  }
}
