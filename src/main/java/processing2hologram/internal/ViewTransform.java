package processing2hologram.internal;

/** Camera and frustum values for one quilt view. */
public final class ViewTransform {
  public final float eyeX;
  public final float eyeY;
  public final float eyeZ;
  public final float centerX;
  public final float centerY;
  public final float centerZ;
  public final float upX;
  public final float upY;
  public final float upZ;
  public final float left;
  public final float right;
  public final float bottom;
  public final float top;
  public final float near;
  public final float far;

  public ViewTransform(
      float eyeX, float eyeY, float eyeZ,
      float centerX, float centerY, float centerZ,
      float upX, float upY, float upZ,
      float left, float right, float bottom, float top,
      float near, float far) {
    this.eyeX = eyeX;
    this.eyeY = eyeY;
    this.eyeZ = eyeZ;
    this.centerX = centerX;
    this.centerY = centerY;
    this.centerZ = centerZ;
    this.upX = upX;
    this.upY = upY;
    this.upZ = upZ;
    this.left = left;
    this.right = right;
    this.bottom = bottom;
    this.top = top;
    this.near = near;
    this.far = far;
  }
}

