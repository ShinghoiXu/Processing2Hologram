package processing2hologram;

import processing.opengl.PGraphics3D;
import processing2hologram.internal.ViewTransform;

/**
 * Describes the center camera from which the horizontal Looking Glass view rig is derived.
 *
 * <p>The rig uses parallel cameras and asymmetric frusta. This keeps the target plane fixed
 * across views and avoids the vertical disparity produced by toe-in cameras.</p>
 */
public final class HolographicCamera {
  private float eyeX;
  private float eyeY;
  private float eyeZ;
  private float targetX;
  private float targetY;
  private float targetZ;
  private float upX = 0f;
  private float upY = 1f;
  private float upZ = 0f;
  private float verticalFovDegrees = 40f;
  private float nearClip = 1f;
  private float farClip = 10_000f;
  private float depthScale = 1f;

  HolographicCamera(int viewWidth, int viewHeight) {
    targetX = viewWidth * 0.5f;
    targetY = viewHeight * 0.5f;
    targetZ = 0f;
    float distance = viewHeight * 0.5f
        / (float) Math.tan(Math.toRadians(verticalFovDegrees * 0.5f));
    eyeX = targetX;
    eyeY = targetY;
    eyeZ = targetZ + distance;
  }

  public HolographicCamera target(float x, float y, float z) {
    float dx = x - targetX;
    float dy = y - targetY;
    float dz = z - targetZ;
    targetX = x;
    targetY = y;
    targetZ = z;
    eyeX += dx;
    eyeY += dy;
    eyeZ += dz;
    return this;
  }

  public HolographicCamera eye(float x, float y, float z) {
    eyeX = x;
    eyeY = y;
    eyeZ = z;
    return this;
  }

  public HolographicCamera lookAt(
      float eyeX, float eyeY, float eyeZ,
      float targetX, float targetY, float targetZ) {
    return lookAt(eyeX, eyeY, eyeZ, targetX, targetY, targetZ, 0f, 1f, 0f);
  }

  public HolographicCamera lookAt(
      float eyeX, float eyeY, float eyeZ,
      float targetX, float targetY, float targetZ,
      float upX, float upY, float upZ) {
    this.eyeX = eyeX;
    this.eyeY = eyeY;
    this.eyeZ = eyeZ;
    this.targetX = targetX;
    this.targetY = targetY;
    this.targetZ = targetZ;
    this.upX = upX;
    this.upY = upY;
    this.upZ = upZ;
    validateBasis();
    return this;
  }

  /** Moves the center eye along its current viewing direction while preserving the target. */
  public HolographicCamera distance(float distance) {
    if (!Float.isFinite(distance) || distance <= 0f) {
      throw new IllegalArgumentException("Camera distance must be positive and finite");
    }
    float[] forward = normalized(targetX - eyeX, targetY - eyeY, targetZ - eyeZ, "view direction");
    eyeX = targetX - forward[0] * distance;
    eyeY = targetY - forward[1] * distance;
    eyeZ = targetZ - forward[2] * distance;
    return this;
  }

  public HolographicCamera fov(float verticalDegrees) {
    if (!Float.isFinite(verticalDegrees) || verticalDegrees <= 1f || verticalDegrees >= 179f) {
      throw new IllegalArgumentException("Vertical field of view must be between 1 and 179 degrees");
    }
    verticalFovDegrees = verticalDegrees;
    return this;
  }

  public HolographicCamera clip(float near, float far) {
    if (!Float.isFinite(near) || !Float.isFinite(far) || near <= 0f || far <= near) {
      throw new IllegalArgumentException("Clip planes must satisfy 0 < near < far");
    }
    nearClip = near;
    farClip = far;
    return this;
  }

  /** Scales the display's physical view cone. Zero produces a flat image; one is native depth. */
  public HolographicCamera depthScale(float scale) {
    if (!Float.isFinite(scale) || scale < 0f || scale > 2f) {
      throw new IllegalArgumentException("Depth scale must be finite and between 0 and 2");
    }
    depthScale = scale;
    return this;
  }

  public float eyeX() { return eyeX; }
  public float eyeY() { return eyeY; }
  public float eyeZ() { return eyeZ; }
  public float targetX() { return targetX; }
  public float targetY() { return targetY; }
  public float targetZ() { return targetZ; }
  public float fov() { return verticalFovDegrees; }
  public float nearClip() { return nearClip; }
  public float farClip() { return farClip; }
  public float depthScale() { return depthScale; }

  public ViewTransform viewTransform(
      int viewIndex, int viewCount, float viewAspect, float displayViewConeDegrees) {
    if (viewIndex < 0 || viewIndex >= viewCount || viewCount < 1) {
      throw new IllegalArgumentException("View index is outside the quilt view range");
    }
    if (!Float.isFinite(viewAspect) || viewAspect <= 0f) {
      throw new IllegalArgumentException("View aspect ratio must be positive");
    }

    float[] forward = normalized(targetX - eyeX, targetY - eyeY, targetZ - eyeZ, "view direction");
    float[] requestedUp = normalized(upX, upY, upZ, "up vector");
    float[] right = normalized(
        forward[1] * requestedUp[2] - forward[2] * requestedUp[1],
        forward[2] * requestedUp[0] - forward[0] * requestedUp[2],
        forward[0] * requestedUp[1] - forward[1] * requestedUp[0],
        "camera right vector");
    float[] correctedUp = new float[] {
        right[1] * forward[2] - right[2] * forward[1],
        right[2] * forward[0] - right[0] * forward[2],
        right[0] * forward[1] - right[1] * forward[0]
    };

    float focusDistance = distance(eyeX, eyeY, eyeZ, targetX, targetY, targetZ);
    float normalizedView = viewCount == 1 ? 0f : viewIndex / (float) (viewCount - 1) - 0.5f;
    float angleDegrees = normalizedView * displayViewConeDegrees * depthScale;
    float lateralOffset = focusDistance * (float) Math.tan(Math.toRadians(angleDegrees));

    float offsetX = right[0] * lateralOffset;
    float offsetY = right[1] * lateralOffset;
    float offsetZ = right[2] * lateralOffset;

    float halfTop = nearClip * (float) Math.tan(Math.toRadians(verticalFovDegrees * 0.5f));
    float halfRight = halfTop * viewAspect;
    float frustumShift = -nearClip * lateralOffset / focusDistance;

    return new ViewTransform(
        eyeX + offsetX, eyeY + offsetY, eyeZ + offsetZ,
        targetX + offsetX, targetY + offsetY, targetZ + offsetZ,
        correctedUp[0], correctedUp[1], correctedUp[2],
        -halfRight + frustumShift, halfRight + frustumShift,
        -halfTop, halfTop, nearClip, farClip);
  }

  void apply(
      PGraphics3D graphics, int viewIndex, int viewCount,
      float viewAspect, float displayViewConeDegrees) {
    ViewTransform transform = viewTransform(viewIndex, viewCount, viewAspect, displayViewConeDegrees);
    graphics.camera(
        transform.eyeX, transform.eyeY, transform.eyeZ,
        transform.centerX, transform.centerY, transform.centerZ,
        transform.upX, transform.upY, transform.upZ);
    graphics.frustum(
        transform.left, transform.right, transform.bottom, transform.top,
        transform.near, transform.far);
  }

  private void validateBasis() {
    float[] forward = normalized(targetX - eyeX, targetY - eyeY, targetZ - eyeZ, "view direction");
    float[] up = normalized(upX, upY, upZ, "up vector");
    float dot = Math.abs(forward[0] * up[0] + forward[1] * up[1] + forward[2] * up[2]);
    if (dot > 0.999f) {
      throw new IllegalArgumentException("Camera up vector cannot be parallel to the view direction");
    }
  }

  private static float[] normalized(float x, float y, float z, String label) {
    float length = (float) Math.sqrt(x * x + y * y + z * z);
    if (!Float.isFinite(length) || length < 1e-6f) {
      throw new IllegalArgumentException("Invalid " + label);
    }
    return new float[] {x / length, y / length, z / length};
  }

  private static float distance(float ax, float ay, float az, float bx, float by, float bz) {
    float dx = ax - bx;
    float dy = ay - by;
    float dz = az - bz;
    return (float) Math.sqrt(dx * dx + dy * dy + dz * dz);
  }
}

