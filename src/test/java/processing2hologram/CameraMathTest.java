package processing2hologram;

import processing2hologram.internal.ViewTransform;

/** Dependency-free unit checks runnable with the JDK bundled in Processing. */
public final class CameraMathTest {
  private static final float EPSILON = 0.0005f;

  public static void main(String[] args) {
    portraitSettingsAreConsistent();
    centerViewIsSymmetric();
    outerViewsMoveInOppositeDirections();
    offAxisFrustumKeepsFocusPlaneStable();
    invalidInputsAreRejected();
    System.out.println("CameraMathTest: all checks passed");
  }

  private static void portraitSettingsAreConsistent() {
    QuiltSettings settings = QuiltSettings.portrait();
    check(settings.viewCount() == 48, "Portrait must contain 48 views");
    check(settings.viewWidth() == 420, "Portrait view width must be 420");
    check(settings.viewHeight() == 560, "Portrait view height must be 560");
    close(settings.viewAspect(), 0.75f, "Portrait view aspect");
  }

  private static void centerViewIsSymmetric() {
    HolographicCamera camera = new HolographicCamera(420, 560);
    ViewTransform center = camera.viewTransform(0, 1, 0.75f, 40f);
    close(center.left, -center.right, "Center frustum horizontal symmetry");
    close(center.bottom, -center.top, "Center frustum vertical symmetry");
    close(center.eyeX, 210f, "Default center eye X");
    close(center.eyeY, 280f, "Default center eye Y");
  }

  private static void outerViewsMoveInOppositeDirections() {
    HolographicCamera camera = new HolographicCamera(420, 560);
    ViewTransform left = camera.viewTransform(0, 48, 0.75f, 40f);
    ViewTransform right = camera.viewTransform(47, 48, 0.75f, 40f);
    check(left.eyeX < camera.eyeX(), "First view must be left of center");
    check(right.eyeX > camera.eyeX(), "Last view must be right of center");
    close(camera.eyeX() - left.eyeX, right.eyeX - camera.eyeX(), "Outer eye symmetry");
  }

  private static void offAxisFrustumKeepsFocusPlaneStable() {
    HolographicCamera camera = new HolographicCamera(420, 560);
    ViewTransform left = camera.viewTransform(0, 48, 0.75f, 40f);
    ViewTransform right = camera.viewTransform(47, 48, 0.75f, 40f);
    float leftCenter = (left.left + left.right) * 0.5f;
    float rightCenter = (right.left + right.right) * 0.5f;
    check(leftCenter > 0f, "Left eye frustum must shift right");
    check(rightCenter < 0f, "Right eye frustum must shift left");
    close(leftCenter, -rightCenter, "Outer frustum symmetry");
  }

  private static void invalidInputsAreRejected() {
    expectFailure(() -> new QuiltSettings(100, 100, 3, 2, 0.75f));
    HolographicCamera camera = new HolographicCamera(420, 560);
    expectFailure(() -> camera.fov(180f));
    expectFailure(() -> camera.clip(10f, 1f));
    expectFailure(() -> camera.depthScale(-1f));
  }

  private static void expectFailure(Runnable action) {
    try {
      action.run();
      throw new AssertionError("Expected IllegalArgumentException");
    } catch (IllegalArgumentException expected) {
      // Expected.
    }
  }

  private static void close(float actual, float expected, String label) {
    if (Math.abs(actual - expected) > EPSILON) {
      throw new AssertionError(label + ": expected " + expected + ", got " + actual);
    }
  }

  private static void check(boolean condition, String message) {
    if (!condition) throw new AssertionError(message);
  }
}

