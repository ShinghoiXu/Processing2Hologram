import processing2hologram.*;

LookingGlass hologram;

void setup() {
  size(900, 700, P3D);
  hologram = new LookingGlass(this);
}

void draw() {
  hologram.render(this::drawScene);

  background(0);
  image(hologram.quilt(), 0, 0, width, height);
}
void drawScene(PGraphics pg) {
  pg.background(10);
  pg.lights();
  pg.pushMatrix();
  pg.translate(pg.width * 0.5, pg.height * 0.5);
  pg.fill(255, 120, 60);
  pg.box(130);
  pg.popMatrix();
}
