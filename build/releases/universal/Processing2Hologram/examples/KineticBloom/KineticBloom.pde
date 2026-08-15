import processing2hologram.*;

final int PETAL_LAYERS = 5;
final int PETALS_PER_LAYER = 14;

LookingGlass hologram;
float bloomTime;
float motionDirection = 1;

void setup() {
  size(420, 560, P3D);
  surface.setTitle("Processing2Hologram - Kinetic Bloom");

  hologram = new LookingGlass(this);
  hologram.camera()
      .lookAt(0, -20, 760, 0, 0, 0)
      .fov(37)
      .clip(1, 2400)
      .depthScale(1.0);
}

void draw() {
  if (frameCount == 1) fitWindowToPreview();
  bloomTime += 0.011 * motionDirection;

  hologram.render(this::drawBloom);

  background(8, 5, 17);
  image(hologram.preview(), 0, 0, width, height);
  drawHud("CLICK reverse  |  SPACE pause", motionDirection == 0 ? "paused" : "kinetic bloom");
}

void drawBloom(PGraphics pg) {
  pg.colorMode(RGB, 255);
  pg.background(8, 5, 17);
  pg.ambientLight(28, 20, 48);
  pg.directionalLight(120, 155, 255, -0.35, 0.25, -1);
  pg.pointLight(255, 80, 185, 180, -160, 260);
  pg.pointLight(70, 225, 255, -190, 160, 120);
  pg.noStroke();
  pg.sphereDetail(10);

  pg.pushMatrix();
  pg.rotateX(-0.16 + 0.06 * sin(bloomTime * 1.4));
  pg.rotateZ(bloomTime * 0.18);

  for (int layer = PETAL_LAYERS - 1; layer >= 0; layer--) {
    float layerNorm = layer / (float) (PETAL_LAYERS - 1);
    float radius = 58 + layer * 38;
    float layerRotation = bloomTime * (0.55 + layer * 0.08)
        * (layer % 2 == 0 ? 1 : -1);
    float pulse = 0.5 + 0.5 * sin(bloomTime * 2.2 + layer * 0.9);

    for (int petal = 0; petal < PETALS_PER_LAYER; petal++) {
      float angle = petal * TWO_PI / PETALS_PER_LAYER + layerRotation;
      float z = 54 * sin(angle * 2 + bloomTime * 1.7 + layer * 0.55)
          + map(layer, 0, PETAL_LAYERS - 1, 42, -58);
      float petalLength = 48 + layer * 9 + pulse * 15;

      pg.pushMatrix();
      pg.rotateZ(angle);
      pg.translate(radius, 0, z);
      pg.rotateZ(HALF_PI);
      pg.rotateY(0.38 * sin(bloomTime * 1.6 + angle * 3 + layer));
      pg.ambient(35 + layer * 12, 18, 55);
      pg.specular(255, 210, 245);
      pg.shininess(18 + layer * 8);
      pg.fill(245 - layer * 20, 56 + layer * 24, 190 + pulse * 55);
      pg.box(15 + 7 * (1 - layerNorm), petalLength, 10 + layer * 2.2);
      pg.popMatrix();
    }
  }

  // A luminous center and three orbiting seeds anchor the sculpture at the focal plane.
  pg.emissive(120, 35, 175);
  pg.fill(255, 150, 235);
  pg.sphere(43 + 5 * sin(bloomTime * 2.4));
  pg.emissive(0, 0, 0);

  for (int orbit = 0; orbit < 3; orbit++) {
    float angle = bloomTime * (0.7 + orbit * 0.13) + orbit * TWO_PI / 3;
    pg.pushMatrix();
    pg.rotateX(angle * 0.47 + orbit);
    pg.rotateY(angle);
    pg.translate(235, 0, 0);
    pg.emissive(30, 130 + orbit * 38, 220);
    pg.fill(70, 190 + orbit * 20, 255);
    pg.sphere(10 + orbit * 2);
    pg.emissive(0, 0, 0);
    pg.popMatrix();
  }
  pg.popMatrix();
}

void mousePressed() {
  motionDirection = motionDirection == 0 ? 1 : -motionDirection;
}

void keyPressed() {
  if (key == ' ') motionDirection = motionDirection == 0 ? 1 : 0;
}

void fitWindowToPreview() {
  PGraphics preview = hologram.preview();
  float scale = min(1, min(displayWidth * 0.8f / preview.width,
                           displayHeight * 0.8f / preview.height));
  int newHeight = max(128, round(preview.height * scale));
  int newWidth = max(128, round(newHeight * preview.width / (float) preview.height));
  if (newWidth != width || newHeight != height) surface.setSize(newWidth, newHeight);
}

void drawHud(String controls, String state) {
  noStroke();
  fill(0, 165);
  rect(10, height - 48, width - 20, 38, 7);
  fill(240);
  textSize(11);
  text(controls, 20, height - 30);
  fill(255, 135, 220);
  text(state + "  |  " + (hologram.isConnected() ? "display connected" : "preview only"),
       20, height - 16);
}
