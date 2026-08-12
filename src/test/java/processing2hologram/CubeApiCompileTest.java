package processing2hologram;

import processing.core.PApplet;
import processing.core.PGraphics;

/** Java equivalent of examples/Cube/Cube.pde, used to catch public API drift at compile time. */
public final class CubeApiCompileTest extends PApplet {
  private LookingGlass hologram;
  private float angle;

  @Override
  public void settings() {
    size(900, 700, P3D);
  }

  @Override
  public void setup() {
    hologram = new LookingGlass(this);
    hologram.camera().fov(40).depthScale(1f);
  }

  @Override
  public void draw() {
    angle += 0.012f;
    hologram.render(this::drawScene);
    image(hologram.preview(), 0, 0, width, height);
  }

  private void drawScene(PGraphics graphics) {
    graphics.background(15, 18, 28);
    graphics.lights();
    graphics.pushMatrix();
    graphics.translate(graphics.width * 0.5f, graphics.height * 0.5f);
    graphics.rotateY(angle);
    graphics.box(150);
    graphics.popMatrix();
  }
}

