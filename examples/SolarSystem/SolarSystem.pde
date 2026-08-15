import processing2hologram.*;

final int PLANET_COUNT = 8;
final int ASTEROID_COUNT = 96;
final int STAR_COUNT = 120;
final int ORBIT_SEGMENTS = 112;
final float ECLIPTIC_TILT = -11;

LookingGlass hologram;
Planet[] planets = new Planet[PLANET_COUNT];
PVector moonPosition = new PVector();

float[] asteroidRadius = new float[ASTEROID_COUNT];
float[] asteroidPhase = new float[ASTEROID_COUNT];
float[] asteroidHeight = new float[ASTEROID_COUNT];
float[] asteroidSpeed = new float[ASTEROID_COUNT];
float[] asteroidX = new float[ASTEROID_COUNT];
float[] asteroidY = new float[ASTEROID_COUNT];
float[] asteroidZ = new float[ASTEROID_COUNT];

float[] starX = new float[STAR_COUNT];
float[] starY = new float[STAR_COUNT];
float[] starZ = new float[STAR_COUNT];
float[] starSize = new float[STAR_COUNT];

float solarTime;
float timeScale = 1;
boolean paused;
boolean showGuides = false;
boolean showQuilt;

void setup() {
  size(420, 560, P3D);
  surface.setTitle("Processing2Hologram - Solar System");

  hologram = new LookingGlass(this);
  hologram.camera()
      .lookAt(0, -500, 960, 0, 0, 0)
      .fov(45)
      .clip(1, 3200)
      .depthScale(1.08);

  // Distances and planet sizes are deliberately compressed for a readable hologram.
  planets[0] = new Planet("Mercury", 48, 4.0, 1.65, 7.0, 0.2, color(155, 145, 135));
  planets[1] = new Planet("Venus",   69, 7.0, 1.31, 3.4, 1.4, color(235, 174, 92));
  planets[2] = new Planet("Earth",   94, 7.5, 1.05, 0.0, 2.7, color(55, 135, 245));
  planets[3] = new Planet("Mars",   121, 5.5, 0.86, 1.8, 4.0, color(218, 82, 48));
  planets[4] = new Planet("Jupiter", 176, 17, 0.55, 1.3, 5.1, color(216, 169, 123));
  planets[5] = new Planet("Saturn",  219, 14, 0.43, 2.5, 0.8, color(230, 202, 132));
  planets[6] = new Planet("Uranus",  260, 10.5, 0.31, 0.8, 2.0, color(116, 218, 225));
  planets[7] = new Planet("Neptune", 300, 10, 0.24, 1.8, 3.4, color(65, 94, 235));

  // All random decisions happen once in setup, outside the multiview callback.
  randomSeed(20260815);
  for (int i = 0; i < ASTEROID_COUNT; i++) {
    asteroidRadius[i] = random(143, 158);
    asteroidPhase[i] = random(TWO_PI);
    asteroidHeight[i] = random(-5, 5);
    asteroidSpeed[i] = random(0.23, 0.34);
  }
  for (int i = 0; i < STAR_COUNT; i++) {
    starX[i] = random(-430, 430);
    starY[i] = random(-330, 250);
    starZ[i] = random(-430, 180);
    starSize[i] = random(1.0, 3.2);
  }
  updateSystem();
}

void draw() {
  if (frameCount == 1) fitWindowToPreview();

  if (!paused) {
    solarTime += 0.01 * timeScale;
    // Cache every moving position once before the scene is rendered into all views.
    updateSystem();
  }

  hologram.render(this::drawSolarSystem);

  background(2, 4, 11);
  if (showQuilt) drawContained(hologram.quilt());
  else image(hologram.preview(), 0, 0, width, height);
  drawHud();
}

void updateSystem() {
  for (Planet planet : planets) planet.update(solarTime);

  Planet earth = planets[2];
  float moonAngle = solarTime * 2.8 + 0.7;
  moonPosition.set(
      earth.position.x + cos(moonAngle) * 14,
      earth.position.y - sin(moonAngle) * 2.2,
      earth.position.z + sin(moonAngle) * 14
  );

  for (int i = 0; i < ASTEROID_COUNT; i++) {
    float angle = asteroidPhase[i] + solarTime * asteroidSpeed[i];
    asteroidX[i] = cos(angle) * asteroidRadius[i];
    asteroidY[i] = asteroidHeight[i];
    asteroidZ[i] = sin(angle) * asteroidRadius[i];
  }
}

void drawSolarSystem(PGraphics pg) {
  pg.colorMode(RGB, 255);
  pg.background(2, 4, 11);
  drawStars(pg);

  pg.ambientLight(18, 20, 28);
  pg.pointLight(255, 225, 155, 0, 0, 0);
  pg.directionalLight(25, 45, 80, 0.2, 0.4, -1);

  // The ecliptic is local XZ, whose -Y normal points upward. Rotating the whole
  // system around Z gives that normal the requested gentle diagonal lean.
  pg.pushMatrix();
  pg.rotateZ(radians(ECLIPTIC_TILT));

  if (showGuides) drawEclipticGuide(pg);
  drawOrbits(pg);
  drawAsteroidBelt(pg);
  drawSun(pg);

  for (int i = 0; i < planets.length; i++) drawPlanet(pg, planets[i], i);
  drawMoon(pg);
  pg.popMatrix();
}

void drawStars(PGraphics pg) {
  pg.strokeCap(ROUND);
  for (int i = 0; i < STAR_COUNT; i++) {
    float twinkle = 0.65 + 0.35 * sin(solarTime * 1.7 + i * 1.93);
    pg.stroke(135, 185, 255, 85 + 135 * twinkle);
    pg.strokeWeight(starSize[i] * twinkle);
    pg.point(starX[i], starY[i], starZ[i]);
  }
}

void drawEclipticGuide(PGraphics pg) {
  pg.noFill();
  pg.strokeWeight(0.7);
  pg.stroke(80, 190, 225, 28);
  for (int i = 0; i < 12; i++) {
    float angle = i * TWO_PI / 12.0;
    pg.line(cos(angle) * 34, 0, sin(angle) * 34,
            cos(angle) * 310, 0, sin(angle) * 310);
  }

  // A subtle arrow makes the ecliptic normal explicit without dominating the scene.
  pg.stroke(115, 225, 255, 115);
  pg.strokeWeight(1.4);
  pg.line(0, -36, 0, 0, -150, 0);
  pg.line(0, -150, 0, -9, -132, 0);
  pg.line(0, -150, 0, 9, -132, 0);
}

void drawOrbits(PGraphics pg) {
  pg.noFill();
  pg.strokeWeight(0.8);
  for (Planet planet : planets) {
    pg.stroke(red(planet.bodyColor), green(planet.bodyColor), blue(planet.bodyColor), 72);
    pg.beginShape();
    float inclination = radians(planet.inclination);
    for (int segment = 0; segment < ORBIT_SEGMENTS; segment++) {
      float angle = segment * TWO_PI / ORBIT_SEGMENTS;
      float x = cos(angle) * planet.orbitRadius;
      float baseZ = sin(angle) * planet.orbitRadius;
      pg.vertex(x, -baseZ * sin(inclination), baseZ * cos(inclination));
    }
    pg.endShape(CLOSE);
  }
}

void drawAsteroidBelt(PGraphics pg) {
  pg.strokeCap(ROUND);
  for (int i = 0; i < ASTEROID_COUNT; i++) {
    pg.stroke(190, 175, 155, 115 + (i % 4) * 22);
    pg.strokeWeight(1.0 + (i % 5) * 0.35);
    pg.point(asteroidX[i], asteroidY[i], asteroidZ[i]);
  }
}

void drawSun(PGraphics pg) {
  pg.noStroke();
  pg.sphereDetail(12);
  pg.pushMatrix();
  pg.rotateY(solarTime * 0.23);
  pg.emissive(255, 132, 18);
  pg.fill(255, 174, 42);
  pg.sphere(27 + 1.5 * sin(solarTime * 2.4));
  pg.emissive(0, 0, 0);
  pg.popMatrix();

  pg.strokeWeight(1.3);
  for (int i = 0; i < 18; i++) {
    float angle = i * TWO_PI / 18.0 + solarTime * 0.16;
    float ray = 34 + 5 * sin(solarTime * 2.1 + i * 1.7);
    pg.stroke(255, 150, 35, 115);
    pg.line(cos(angle) * 29, 0, sin(angle) * 29,
            cos(angle) * ray, 0, sin(angle) * ray);
  }
}

void drawPlanet(PGraphics pg, Planet planet, int index) {
  pg.pushMatrix();
  pg.translate(planet.position.x, planet.position.y, planet.position.z);

  pg.pushMatrix();
  pg.rotateY(planet.spin);
  pg.noStroke();
  pg.ambient(red(planet.bodyColor) * 0.45,
             green(planet.bodyColor) * 0.45,
             blue(planet.bodyColor) * 0.45);
  pg.specular(210, 220, 235);
  pg.shininess(index == 2 ? 24 : 10);
  pg.fill(planet.bodyColor);
  pg.sphereDetail(index == 4 || index == 5 ? 12 : 9);
  pg.sphere(planet.radius);
  pg.popMatrix();

  if (index == 5) {
    pg.pushMatrix();
    pg.rotateZ(radians(26.7));
    drawRingBand(pg, 18, 22, 196, 174, 125, 185);
    drawRingBand(pg, 23.5, 28.5, 235, 215, 164, 210);
    drawRingBand(pg, 30, 35, 170, 145, 105, 150);
    pg.popMatrix();
  }
  pg.popMatrix();
}

void drawRingBand(PGraphics pg, float innerRadius, float outerRadius,
                  float redValue, float greenValue, float blueValue, float alphaValue) {
  pg.noStroke();
  pg.fill(redValue, greenValue, blueValue, alphaValue);
  pg.beginShape(TRIANGLE_STRIP);
  for (int segment = 0; segment <= 96; segment++) {
    float angle = segment * TWO_PI / 96.0;
    float cosine = cos(angle);
    float sine = sin(angle);
    pg.vertex(cosine * outerRadius, 0, sine * outerRadius);
    pg.vertex(cosine * innerRadius, 0, sine * innerRadius);
  }
  pg.endShape();
}

void drawMoon(PGraphics pg) {
  Planet earth = planets[2];
  pg.stroke(145, 175, 205, 80);
  pg.strokeWeight(0.8);
  pg.line(earth.position.x, earth.position.y, earth.position.z,
          moonPosition.x, moonPosition.y, moonPosition.z);

  pg.pushMatrix();
  pg.translate(moonPosition.x, moonPosition.y, moonPosition.z);
  pg.noStroke();
  pg.fill(205, 210, 215);
  pg.sphereDetail(6);
  pg.sphere(2.2);
  pg.popMatrix();
}

void keyPressed() {
  if (key == ' ') paused = !paused;
  if (key == 'g' || key == 'G') showGuides = !showGuides;
  if (key == 'q' || key == 'Q') showQuilt = !showQuilt;
  if (key == 's' || key == 'S') hologram.saveQuilt("solar-system");
  if (key == 'r' || key == 'R') {
    solarTime = 0;
    updateSystem();
  }
  if (key == CODED && keyCode == UP) timeScale = min(4, timeScale * 1.25);
  if (key == CODED && keyCode == DOWN) timeScale = max(0.25, timeScale / 1.25);
}

class Planet {
  String name;
  float orbitRadius;
  float radius;
  float angularSpeed;
  float inclination;
  float phase;
  float spin;
  int bodyColor;
  PVector position = new PVector();

  Planet(String name, float orbitRadius, float radius, float angularSpeed,
         float inclination, float phase, int bodyColor) {
    this.name = name;
    this.orbitRadius = orbitRadius;
    this.radius = radius;
    this.angularSpeed = angularSpeed;
    this.inclination = inclination;
    this.phase = phase;
    this.bodyColor = bodyColor;
  }

  void update(float time) {
    float angle = phase + time * angularSpeed;
    float baseZ = sin(angle) * orbitRadius;
    float tilt = radians(inclination);
    position.set(
        cos(angle) * orbitRadius,
        -baseZ * sin(tilt),
        baseZ * cos(tilt)
    );
    spin = time * (2.2 + angularSpeed * 0.7) + phase;
  }
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
  text("SPACE pause   UP/DOWN speed   G guides", 20, height - 47);
  text("Q quilt   S save   R reset", 20, height - 32);
  fill(255, 190, 80);
  text("time x" + nf(timeScale, 1, 2) + "  |  "
       + (hologram.isConnected() ? "display connected" : "preview only"), 20, height - 17);
}

void fitWindowToPreview() {
  PGraphics preview = hologram.preview();
  float scale = min(1, min(displayWidth * 0.8f / preview.width,
                           displayHeight * 0.8f / preview.height));
  int newHeight = max(128, round(preview.height * scale));
  int newWidth = max(128, round(newHeight * preview.width / (float) preview.height));
  if (newWidth != width || newHeight != height) surface.setSize(newWidth, newHeight);
}
