package processing2hologram;

import java.util.Objects;

/** Immutable dimensions and layout of a Looking Glass quilt. */
public final class QuiltSettings {
  private final int width;
  private final int height;
  private final int columns;
  private final int rows;
  private final float viewAspect;

  public QuiltSettings(int width, int height, int columns, int rows, float viewAspect) {
    if (width <= 0 || height <= 0 || columns <= 0 || rows <= 0) {
      throw new IllegalArgumentException("Quilt dimensions and grid counts must be positive");
    }
    if (width % columns != 0 || height % rows != 0) {
      throw new IllegalArgumentException("Quilt dimensions must be divisible by the grid dimensions");
    }
    if (!Float.isFinite(viewAspect) || viewAspect <= 0f) {
      throw new IllegalArgumentException("View aspect ratio must be positive and finite");
    }
    this.width = width;
    this.height = height;
    this.columns = columns;
    this.rows = rows;
    this.viewAspect = viewAspect;
  }

  /** Looking Glass Portrait's standard real-time quilt. */
  public static QuiltSettings portrait() {
    return new QuiltSettings(3360, 3360, 8, 6, 0.75f);
  }

  public int width() {
    return width;
  }

  public int height() {
    return height;
  }

  public int columns() {
    return columns;
  }

  public int rows() {
    return rows;
  }

  public int viewCount() {
    return columns * rows;
  }

  public int viewWidth() {
    return width / columns;
  }

  public int viewHeight() {
    return height / rows;
  }

  public float viewAspect() {
    return viewAspect;
  }

  @Override
  public boolean equals(Object other) {
    if (this == other) return true;
    if (!(other instanceof QuiltSettings that)) return false;
    return width == that.width
        && height == that.height
        && columns == that.columns
        && rows == that.rows
        && Float.compare(viewAspect, that.viewAspect) == 0;
  }

  @Override
  public int hashCode() {
    return Objects.hash(width, height, columns, rows, viewAspect);
  }

  @Override
  public String toString() {
    return width + "x" + height + " (" + columns + "x" + rows + ", aspect " + viewAspect + ")";
  }
}

