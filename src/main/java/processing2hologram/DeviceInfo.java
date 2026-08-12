package processing2hologram;

/** Basic information reported by Looking Glass Bridge for the selected display. */
public final class DeviceInfo {
  private final long index;
  private final String name;
  private final String serial;
  private final float viewConeDegrees;

  public DeviceInfo(long index, String name, String serial, float viewConeDegrees) {
    this.index = index;
    this.name = name == null ? "Looking Glass" : name;
    this.serial = serial == null ? "" : serial;
    this.viewConeDegrees = viewConeDegrees;
  }

  public long index() {
    return index;
  }

  public String name() {
    return name;
  }

  public String serial() {
    return serial;
  }

  public float viewConeDegrees() {
    return viewConeDegrees;
  }

  @Override
  public String toString() {
    String suffix = serial.isBlank() ? "" : " (" + serial + ")";
    return name + suffix;
  }
}

