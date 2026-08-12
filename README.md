# Processing2Hologram

Processing2Hologram is a Processing 4 library that renders a `P3D` scene as a
multi-view quilt and sends it to a Looking Glass display through Looking Glass
Bridge. The first supported platform is Windows and the first validated target
is Looking Glass Portrait.

The library asks the sketch for **how to draw the scene**, rather than accepting
one already-flattened `PGraphics`. It can therefore render the same immutable
scene snapshot from every horizontal camera position with correct visibility and
occlusion.

## Current status

Version `0.1.1` contains the first complete Windows/Portrait pipeline:

- Processing 4 Java Mode and `P3D`
- a scene callback using normal `PGraphics` drawing commands
- parallel horizontal cameras with asymmetric frusta
- Bridge device discovery and device-recommended quilt settings
- Portrait fallback settings: 3360 x 3360, 8 x 6, aspect 0.75
- GPU quilt submission through a small Windows JNI adapter
- a dedicated double-buffered WGL context for Bridge's optical pass
- explicit Bridge-window message processing on Processing's animation thread
- center-view and full-quilt previews when no device is available
- automatic native cleanup through Processing's `dispose` lifecycle

The original `Processing2Hologram_2D` sketch is retained as the historical 2.5D
layer-compositing prototype. New development lives under `src`, `native`, and
`examples`.

## Requirements

- Windows 10 or 11, x64
- Processing 4.4.6 or later
- a sketch using the `P3D` renderer
- Looking Glass Bridge 2.6 or later
- Looking Glass Portrait connected in desktop mode for live hardware output

The runtime adapter locates `bridge_inproc.dll` in the normal Looking Glass
Bridge installation. An advanced deployment may set `LOOKING_GLASS_BRIDGE_DLL`
to its absolute path.

## Quick start

Build the library from PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
```

The installable Processing library is produced at:

```text
build/Processing2Hologram
```

Copy that directory into the `libraries` directory of the Processing
Sketchbook, restart Processing, then open
`File > Examples > Contributed Libraries > Processing2Hologram > Cube`.

The default example is intentionally a single rotating cube:

```java
import processing2hologram.*;

LookingGlass hologram;
float angle;

void setup() {
  size(900, 700, P3D);
  hologram = new LookingGlass(this);
}

void draw() {
  angle += 0.012;                 // update once per animation frame
  hologram.render(this::drawScene);
  image(hologram.preview(), 0, 0, width, height);
}

void drawScene(PGraphics pg) {
  pg.background(15, 18, 28);
  pg.lights();
  pg.pushMatrix();
  pg.translate(pg.width * 0.5, pg.height * 0.5);
  pg.rotateY(angle);
  pg.box(150);
  pg.popMatrix();
}
```

## Scene callback contract

`drawScene()` is called once per quilt view: normally 48 times for Portrait.
It must draw the same scene snapshot every time.

Update these outside the callback, once in `draw()`:

- animation values
- physics and particle simulation
- random or noise seeds that change scene structure
- input-derived object state

Use the callback for drawing only:

- `background`, lights, materials, and shaders
- matrix transforms
- Processing primitives
- `PShape` models and textures

The library owns `camera()`, `perspective()`, and `frustum()` inside holographic
views. Configure the center camera through `hologram.camera()` instead:

```java
hologram.camera()
    .lookAt(210, 280, 800, 210, 280, 0)
    .fov(40)
    .clip(1, 10000)
    .depthScale(1.0);
```

`depthScale(0)` is flat, `1` uses the display's reported view cone, and values up
to `2` exaggerate parallax. Excessive depth can be uncomfortable or leave holes
at the edge of the view cone.

## Runtime behavior

When Bridge and a display are available, construction first verifies that Windows
has enumerated a Looking Glass monitor, then queries the selected
device for its name, serial, view cone, maximum texture size, and recommended
quilt layout. `render()` then submits the completed OpenGL quilt texture to the
Bridge display window. On Windows, Bridge renders its optical pass in a private
double-buffered WGL context that shares Processing's quilt texture. The adapter
also processes Bridge window messages once per submitted frame. This separation
is required for Processing/JOGL interoperability; submitting directly from the
JOGL context can produce a white Bridge window even when the quilt texture is valid.

If no Looking Glass is enumerated, the Bridge SDK is not initialized at all. If
Bridge is unavailable or no display is connected, the sketch stays alive and
uses the standard Portrait quilt settings. `preview()`, `quilt()`, and
`saveQuilt()` remain usable, and `status()` explains the missing live output.

If GPU texture sharing fails during presentation, live submission is disabled
for the remainder of the session instead of repeatedly throwing every frame.
The local preview remains available.

## Public API

- `new LookingGlass(PApplet)` selects the first display
- `render(SceneRenderer)` renders and presents one scene snapshot
- `camera()` returns the center-camera configuration
- `preview()` returns the center-nearest view
- `quilt()` returns the latest full quilt
- `saveQuilt(baseName)` writes a correctly tagged PNG filename
- `device()` returns connected device information, or `null` offline
- `quiltSettings()` returns the active dimensions and grid
- `isConnected()` reports whether live presentation is still active
- `status()` returns a concise connection or failure message
- `close()` releases Bridge and Processing graphics resources

## Build and verification

`build.ps1` uses the JDK and `core.jar` bundled with Processing, plus CMake and
the Visual Studio 2022 C++ toolchain. It does not download dependencies.

The normal build compiles:

- all Java sources
- the Windows JNI adapter
- camera/quilt unit checks
- a Java compile-equivalent of the Cube example
- a Processing-ready distribution JAR with the native DLL embedded

To also open a hidden Processing OpenGL surface and verify that all 48 Portrait
views contain the demo cube, run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -RunGraphicsTest
```

The optional hardware diagnostic is:

```powershell
& 'C:\Program Files\Processing\app\resources\jdk\bin\java.exe' `
  -cp 'build\Processing2Hologram\library\Processing2Hologram.jar' `
  processing2hologram.BridgeDiagnostics
```

It is safe to run without hardware: it reports that no display is connected and
does not initialize Bridge. With a display connected, it prints the selected
device and its calibration-derived quilt settings.

## Known boundaries

- Windows x64 is the only current live-output backend.
- The main sketch renderer must be `P3D`.
- The scene callback is multi-pass and may be expensive for complex sketches.
- Direct calls to `camera`, `perspective`, or `frustum` inside the callback will
  replace the holographic view transform and are unsupported.
- Processing's public OpenGL surface does not provide a stable texture-sharing
  contract; the small interop section is deliberately isolated for future
  Processing/JOGL compatibility fixes.
- A single already-rendered color `PGraphics` cannot be reconstructed as correct
  multiview geometry. An RGB-D approximation is a possible later feature, not
  part of this release.

## Troubleshooting

If the normal Processing preview shows the cube but Portrait is blank or white:

1. Confirm the sketch reports `Connected to Looking Glass Portrait` rather than
   preview-only mode.
2. Confirm Looking Glass Bridge is running and Portrait is enabled as a 1536 x
   2048 Windows display.
3. Replace the complete installed `Processing2Hologram` library directory with
   the newly built `build/Processing2Hologram` directory, then restart Processing.
   Processing keeps the old JAR and embedded native DLL loaded until restart.
4. Use version `0.1.1` or later. Version `0.1.0` submitted from JOGL's context and
   can leave Bridge 2.6.x showing a fully white window on Windows.

## References

- [Processing render techniques](https://processing.org/tutorials/rendering/)
- [Processing library template](https://processing.github.io/processing-library-template/)
- [Looking Glass Bridge native API](https://lfdocs.lookingglassfactory.com/software/looking-glass-bridge-sdk/native-function-reference)
- [Looking Glass quilt format](https://lookingglassfactory.com/tutorial/what-is-a-quilt)

## License

MIT. See [LICENSE](LICENSE).
