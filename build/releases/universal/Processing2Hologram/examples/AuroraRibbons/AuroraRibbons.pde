import processing2hologram.*;

final int RIBBON_COUNT = 7;
final int RIBBON_SEGMENTS = 64;
final int STAR_COUNT = 90;

LookingGlass hologram;
float auroraTime;
boolean paused;

float[] starX = new float[STAR_COUNT];
float[] starY = new float[STAR_COUNT];
float[] starZ = new float[STAR_COUNT];
float[] starSize = new float[STAR_COUNT];

void setup() {
  size(420, 560, P3D);
  surface.setTitle("Processing2Hologram - Aurora Ribbons");

  hologram = new LookingGlass(this);
  hologram.camera()
      .lookAt(0, 0, 720, 0, 0, 0)
      .fov(38)
      .clip(1, 2200)
      .depthScale(1.15);

  // Randomness is resolved once, never inside the per-view callback.
  randomSeed(240519);
  for (int i = 0; i < STAR_COUNT; i++) {
    starX[i] = random(-300, 300);
    starY[i] = random(-230, 230);
    starZ[i] = random(-280, 180);
    starSize[i] = random(1.2, 3.8);
  }
}

void draw() {
  if (frameCount == 1) fitWindowToPreview();
  if (!paused) auroraTime += 0.014;

  // auroraTime changes once here. drawAurora() sees the same instant in every view.
  hologram.render(this::drawAurora);

  background(3, 5, 14);
  image(hologram.preview(), 0, 0, width, height);
  drawHud("SPACE pause  |  S save quilt", paused ? "paused" : "flowing");
}

void drawAurora(PGraphics pg) {
  pg.colorMode(RGB, 255);
  pg.background(3, 5, 14);

  pg.strokeCap(ROUND);
  for (int i = 0; i < STAR_COUNT; i++) {
    float twinkle = 0.55 + 0.45 * sin(auroraTime * 2.0 + i * 1.71);
    pg.stroke(115, 185, 255, 80 + 150 * twinkle);
    pg.strokeWeight(starSize[i] * twinkle);
    pg.point(starX[i], starY[i], starZ[i]);
  }

  pg.noStroke();
  pg.colorMode(HSB, 360, 100, 100, 100);
  for (int ribbon = 0; ribbon < RIBBON_COUNT; ribbon++) {
    float band = map(ribbon, 0, RIBBON_COUNT - 1, -1, 1);
    float baseY = band * 145;
    float phase = auroraTime * (0.72 + ribbon * 0.035) + ribbon * 0.83;

    pg.beginShape(TRIANGLE_STRIP);
    for (int segment = 0; segment <= RIBBON_SEGMENTS; segment++) {
      float u = segment / (float) RIBBON_SEGMENTS;
      float x = lerp(-285, 285, u);
      float y = baseY
          + 30 * sin(u * TWO_PI * 1.35 + phase)
          + 10 * sin(u * TWO_PI * 3.2 - phase * 1.7);
      float z = 105 * sin(u * TWO_PI * 0.82 - phase * 0.9)
          + band * 62
          + 18 * cos(u * TWO_PI * 2.0 + ribbon);
      float halfWidth = 10 + 5 * sin(u * PI);
      float hue = (165 + ribbon * 22 + u * 58 + auroraTime * 8) % 360;

      pg.fill(hue, 72, 100, 72);
      pg.vertex(x, y - halfWidth, z - 5);
      pg.fill((hue + 34) % 360, 55, 100, 22);
      pg.vertex(x, y + halfWidth, z + 5);
    }
    pg.endShape();
  }

  // Bright beads make the ribbon depth easy to read on a Looking Glass.
  pg.sphereDetail(7);
  for (int ribbon = 0; ribbon < RIBBON_COUNT; ribbon++) {
    float u = (auroraTime * 0.055 + ribbon * 0.137) % 1.0;
    float band = map(ribbon, 0, RIBBON_COUNT - 1, -1, 1);
    float phase = auroraTime * (0.72 + ribbon * 0.035) + ribbon * 0.83;
    float x = lerp(-285, 285, u);
    float y = band * 145 + 30 * sin(u * TWO_PI * 1.35 + phase)
        + 10 * sin(u * TWO_PI * 3.2 - phase * 1.7);
    float z = 105 * sin(u * TWO_PI * 0.82 - phase * 0.9)
        + band * 62 + 18 * cos(u * TWO_PI * 2.0 + ribbon);
    pg.pushMatrix();
    pg.translate(x, y, z);
    pg.fill((175 + ribbon * 24) % 360, 35, 100, 100);
    pg.sphere(6);
    pg.popMatrix();
  }
  pg.colorMode(RGB, 255);
}

void keyPressed() {
  if (key == ' ') paused = !paused;
  if (key == 's' || key == 'S') hologram.saveQuilt("aurora-ribbons");
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
  fill(235);
  textSize(11);
  text(controls, 20, height - 30);
  fill(125, 220, 255);
  text(state + "  |  " + (hologram.isConnected() ? "display connected" : "preview only"),
       20, height - 16);
}
