import processing2hologram.*;

LookingGlass hologram;
float angle;

void setup() {
  size(900, 700, P3D);
  hologram = new LookingGlass(this);

  // The library owns the per-view camera. The user describes only the center camera.
  hologram.camera()
      .fov(40)
      .depthScale(1.0);
}

void draw() {
  // Update animation exactly once. drawScene() is called 48 times per frame on Portrait.
  angle += 0.012;
  hologram.render(this::drawScene);

  background(18);
  image(hologram.preview(), 0, 0, width, height);

  fill(255);
  text("Processing2Hologram - " + hologram.status(), 16, height - 18);
}

void drawScene(PGraphics pg) {
  pg.background(15, 18, 28);
  pg.lights();

  pg.pushMatrix();
  pg.translate(pg.width * 0.5, pg.height * 0.5, 0);
  pg.rotateX(-0.35);
  pg.rotateY(angle);
  pg.noStroke();
  pg.fill(80, 175, 255);
  pg.box(150);
  pg.popMatrix();
}
