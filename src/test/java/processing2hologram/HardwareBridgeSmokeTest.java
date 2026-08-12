package processing2hologram;

import java.awt.GraphicsDevice;
import java.awt.GraphicsEnvironment;
import java.awt.Rectangle;
import java.awt.Robot;
import java.awt.image.BufferedImage;
import javax.imageio.ImageIO;
import java.nio.file.Path;
import java.nio.file.Files;
import java.nio.file.StandardOpenOption;
import processing.core.PApplet;
import processing.core.PGraphics;
import processing.opengl.PGraphicsOpenGL;
import processing.opengl.Texture;

/** Connected-display diagnostic that compares Processing and Bridge reads of one quilt texture. */
public final class HardwareBridgeSmokeTest extends PApplet {
  private LookingGlass hologram;
  private final Path outputDirectory = Path.of(
      System.getProperty("processing2hologram.diagnosticOutput", "build/hardware-diagnostic"))
      .toAbsolutePath();

  public static void main(String[] args) {
    Path output = Path.of(
        System.getProperty("processing2hologram.diagnosticOutput", "build/hardware-diagnostic"))
        .toAbsolutePath();
    output.toFile().mkdirs();
    try {
      Files.deleteIfExists(output.resolve("processing-quilt.png"));
      Files.deleteIfExists(output.resolve("bridge-quilt.png"));
      Files.writeString(output.resolve("diagnostic-status.txt"), "JVM started\n");
    } catch (Exception failure) {
      failure.printStackTrace();
      System.exit(1);
    }
    PApplet.main(HardwareBridgeSmokeTest.class.getName());
  }

  @Override
  public void settings() {
    size(320, 240, P3D);
  }

  @Override
  public void setup() {
    try {
      mark("Processing setup entered");
      surface.setTitle("Processing2Hologram hardware diagnostic");
      hologram = new LookingGlass(this);
      mark("LookingGlass constructed: " + hologram.status());
      if (!hologram.isConnected()) {
        throw new IllegalStateException("Portrait did not connect: " + hologram.status());
      }
    } catch (Throwable failure) {
      mark("SETUP FAILURE: " + failure);
      Runtime.getRuntime().halt(1);
    }
  }

  @Override
  public void draw() {
    try {
      hologram.render(this::drawScene); // Initialize all shared textures.
      hologram.render(this::drawScene);
      mark("Two quilt frames rendered and submitted");

      Texture texture = ((PGraphicsOpenGL) hologram.quilt()).getTexture();
      String textureInfo = "Quilt texture: id=" + Integer.toUnsignedLong(texture.glName)
          + ", format=0x" + Integer.toHexString(texture.glFormat)
          + ", invertedX=" + texture.invertedX() + ", invertedY=" + texture.invertedY();
      println(textureInfo);
      mark(textureInfo);

      delay(1000);
      capturePortraitScreen();
      mark("Portrait screen captured before Bridge texture export");

      outputDirectory.toFile().mkdirs();
      String processingPath = outputDirectory.resolve("processing-quilt.png").toString();
      String bridgePath = outputDirectory.resolve("bridge-quilt.png").toString();
      hologram.quilt().save(processingPath);
      hologram.saveBridgeQuilt(bridgePath);
      mark("Both quilt files saved");

      println("Processing quilt: " + processingPath);
      println("Bridge quilt: " + bridgePath);
      println("Leave the diagnostic visible on Portrait for one second...");
      System.out.flush();
      System.err.flush();
      delay(1000);
      mark("Closing LookingGlass session");
      hologram.close();
      mark("Hardware diagnostic complete; close returned");
      Runtime.getRuntime().halt(0);
    } catch (Throwable failure) {
      mark("DRAW FAILURE: " + failure);
      failure.printStackTrace();
      Runtime.getRuntime().halt(1);
    }
  }

  private void drawScene(PGraphics graphics) {
    graphics.background(15, 18, 28);
    graphics.lights();
    graphics.pushMatrix();
    graphics.translate(graphics.width * 0.5f, graphics.height * 0.5f, 0f);
    graphics.rotateX(-0.35f);
    graphics.rotateY(0.55f);
    graphics.noStroke();
    graphics.fill(80, 175, 255);
    graphics.box(150);
    graphics.popMatrix();
  }

  private void mark(String message) {
    try {
      Files.writeString(outputDirectory.resolve("diagnostic-status.txt"),
          message + System.lineSeparator(), StandardOpenOption.CREATE, StandardOpenOption.APPEND);
    } catch (Exception failure) {
      failure.printStackTrace();
    }
  }

  private void capturePortraitScreen() throws Exception {
    GraphicsDevice portrait = null;
    for (GraphicsDevice device : GraphicsEnvironment.getLocalGraphicsEnvironment().getScreenDevices()) {
      Rectangle bounds = device.getDefaultConfiguration().getBounds();
      if (bounds.width == 1536 && bounds.height == 2048) {
        portrait = device;
        break;
      }
    }
    if (portrait == null) throw new IllegalStateException("1536x2048 Portrait screen not found");
    Rectangle bounds = portrait.getDefaultConfiguration().getBounds();
    BufferedImage screenshot = new Robot(portrait).createScreenCapture(bounds);
    ImageIO.write(screenshot, "png", outputDirectory.resolve("portrait-screen.png").toFile());
  }
}
