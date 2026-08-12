package processing2hologram.internal;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;

/** Extracts the bundled JNI adapter without changing the process-wide native library path. */
final class NativeLibraryLoader {
  private static boolean loaded;

  private NativeLibraryLoader() {}

  static synchronized void load() {
    if (loaded) return;
    if (!System.getProperty("os.name", "").toLowerCase().contains("win")) {
      throw new UnsupportedOperationException("Processing2Hologram currently supports Windows only");
    }

    String override = System.getProperty("processing2hologram.native");
    if (override != null && !override.isBlank()) {
      System.load(Path.of(override).toAbsolutePath().toString());
      loaded = true;
      return;
    }

    String resource = "/native/windows-amd64/processing2hologram.dll";
    try (InputStream input = NativeLibraryLoader.class.getResourceAsStream(resource)) {
      if (input == null) {
        // Useful while developing from unpacked classes and for standard Processing native layouts.
        System.loadLibrary("processing2hologram");
      } else {
        Path directory = Files.createTempDirectory("processing2hologram-native-");
        Path library = directory.resolve("processing2hologram.dll");
        Files.copy(input, library, StandardCopyOption.REPLACE_EXISTING);
        library.toFile().deleteOnExit();
        directory.toFile().deleteOnExit();
        System.load(library.toAbsolutePath().toString());
      }
      loaded = true;
    } catch (IOException exception) {
      throw new UnsatisfiedLinkError("Could not extract Processing2Hologram native adapter: "
          + exception.getMessage());
    }
  }
}

