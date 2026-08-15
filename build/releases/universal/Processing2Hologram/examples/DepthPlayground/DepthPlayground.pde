import processing2hologram.*;

final int PORTAL_COUNT = 11;

LookingGlass hologram;
float depthScale = 1.0;
float depthSpread = 1.0;
float bridgeZoom = 1.0;
float sceneTime;
boolean mouseControl = true;
boolean showQuilt;
boolean pointerActive;

void setup() {
  size(420, 560, P3D);
  surface.setTitle("Processing2Hologram - Depth Playground");

  hologram = new LookingGlass(this);
  hologram.camera()
      .lookAt(0, 0, 760, 0, 0, 0)
      .fov(38)
      .clip(1, 2600)
      .depthScale(depthScale);
}

void draw() {
  if (frameCount == 1) fitWindowToPreview();
  sceneTime += 0.01;

  if (mouseControl && pointerActive
      && mouseX >= 0 && mouseX <= width && mouseY >= 0 && mouseY <= height) {
    float targetDepth = map(mouseX, 0, width, 0, 1.65);
    float targetSpread = map(mouseY, 0, height, 0.55, 1.45);
    depthScale = lerp(depthScale, targetDepth, 0.08);
    depthSpread = lerp(depthSpread, targetSpread, 0.08);
  }

  // Camera depth and Bridge zoom are safe to update once before render().
  hologram.camera().depthScale(depthScale);
  hologram.zoom(bridgeZoom);
  hologram.render(this::drawDepthScene);

  background(4, 4, 12);
  if (showQuilt) {
    drawContained(hologram.quilt());
  } else {
    image(hologram.preview(), 0, 0, width, height);
  }
  drawHud();
}

void drawDepthScene(PGraphics pg) {
  pg.colorMode(RGB, 255);
  pg.background(4, 4, 12);
  pg.ambientLight(24, 22, 42);
  pg.directionalLight(80, 155, 255, -0.4, 0.2, -1);
  pg.pointLight(255, 55, 170, 150, -150, 240);
  pg.noStroke();

  for (int i = 0; i < PORTAL_COUNT; i++) {
    float normalized = map(i, 0, PORTAL_COUNT - 1, -1, 1);
    float z = normalized * 290 * depthSpread;
    float size = 250 - 48 * abs(normalized)
        + 8 * sin(sceneTime * 1.7 + i * 0.8);
    float rotation = sceneTime * (i % 2 == 0 ? 0.18 : -0.18) + i * 0.29;
    drawPortalFrame(pg, size, z, rotation, i);
  }

  pg.noStroke();
  pg.sphereDetail(8);
  pg.pushMatrix();
  pg.rotateY(sceneTime * 0.55);
  pg.rotateX(sceneTime * 0.31);
  pg.emissive(120, 25, 170);
  pg.fill(255, 115, 225);
  pg.sphere(35 + 4 * sin(sceneTime * 2.2));
  pg.emissive(0, 0, 0);
  pg.popMatrix();
}

void drawPortalFrame(PGraphics pg, float size, float z, float rotation, int index) {
  float halfSize = size * 0.5;
  pg.pushMatrix();
  pg.translate(0, 0, z);
  pg.rotateZ(rotation);
  pg.noFill();
  pg.strokeWeight(1.6 + (index % 3) * 0.45);
  if (index % 2 == 0) pg.stroke(45, 190, 255, 220);
  else pg.stroke(255, 65, 185, 220);
  pg.beginShape();
  pg.vertex(-halfSize, -halfSize, 0);
  pg.vertex(halfSize, -halfSize, 0);
  pg.vertex(halfSize, halfSize, 0);
  pg.vertex(-halfSize, halfSize, 0);
  pg.vertex(-halfSize, -halfSize, 0);
  pg.endShape();
  pg.popMatrix();
}

void keyPressed() {
  if (key == 'm' || key == 'M') mouseControl = !mouseControl;
  if (key == 'q' || key == 'Q') showQuilt = !showQuilt;
  if (key == 's' || key == 'S') hologram.saveQuilt("depth-playground");
  if (key == 'r' || key == 'R') {
    depthScale = 1;
    depthSpread = 1;
    bridgeZoom = 1;
    pointerActive = false;
  }
  if (key == '+' || key == '=') bridgeZoom = min(1.4, bridgeZoom + 0.05);
  if (key == '-' || key == '_') bridgeZoom = max(0.65, bridgeZoom - 0.05);
}

void mouseMoved() {
  pointerActive = true;
}

void mouseDragged() {
  pointerActive = true;
}

void drawContained(PImage source) {
  float scale = min(width / (float) source.width, height / (float) source.height);
  float drawWidth = source.width * scale;
  float drawHeight = source.height * scale;
  image(source, (width - drawWidth) * 0.5, (height - drawHeight) * 0.5, drawWidth, drawHeight);
}

void drawHud() {
  noStroke();
  fill(0, 185);
  rect(10, height - 66, width - 20, 56, 7);
  fill(240);
  textSize(11);
  text("Mouse: depth / spread   M lock   Q quilt   S save", 20, height - 47);
  text("+/- zoom   R reset", 20, height - 32);
  fill(105, 210, 255);
  text("depth " + nf(depthScale, 1, 2) + "   spread " + nf(depthSpread, 1, 2)
       + "   zoom " + nf(bridgeZoom, 1, 2), 20, height - 17);
}

void fitWindowToPreview() {
  PGraphics preview = hologram.preview();
  float scale = min(1, min(displayWidth * 0.8f / preview.width,
                           displayHeight * 0.8f / preview.height));
  int newHeight = max(128, round(preview.height * scale));
  int newWidth = max(128, round(newHeight * preview.width / (float) preview.height));
  if (newWidth != width || newHeight != height) surface.setSize(newWidth, newHeight);
}
