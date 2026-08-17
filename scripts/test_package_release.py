from pathlib import Path
import sys
import tempfile
import unittest
from zipfile import ZipFile


sys.path.insert(0, str(Path(__file__).resolve().parent))

from package_release import (  # noqa: E402
    ReleaseZipError,
    create_release_zip,
    validate_release_zip,
)


class PackageReleaseTest(unittest.TestCase):
    def test_created_archive_uses_posix_names_and_explicit_directories(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            source = temporary / "Processing2Hologram"
            (source / "library").mkdir(parents=True)
            (source / "examples" / "BasicExample").mkdir(parents=True)
            (source / "library" / "Processing2Hologram.jar").write_bytes(b"jar")
            (source / "library.properties").write_text(
                "name=Processing2Hologram\n", encoding="utf-8"
            )
            (source / "examples" / "BasicExample" / "BasicExample.pde").write_text(
                "void setup() {}\n", encoding="utf-8"
            )
            archive_path = temporary / "Processing2Hologram.zip"

            summary = create_release_zip(source, archive_path)

            with ZipFile(archive_path) as archive:
                names = archive.namelist()
            self.assertEqual(summary.backslash_entries, 0)
            self.assertFalse(any("\\" in name for name in names))
            self.assertIn("Processing2Hologram/", names)
            self.assertIn("Processing2Hologram/library/", names)
            self.assertIn("Processing2Hologram/examples/BasicExample/", names)
            self.assertIn(
                "Processing2Hologram/library/Processing2Hologram.jar", names
            )
            self.assertIn(
                "Processing2Hologram/examples/BasicExample/BasicExample.pde", names
            )

    def test_validator_rejects_windows_style_entry_names(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            archive_path = Path(temporary_directory) / "bad.zip"
            posix_name = "Processing2Hologram/library/Processing2Hologram.jar"
            with ZipFile(archive_path, "w") as archive:
                archive.writestr(posix_name, b"jar")

            # zipfile itself normalizes separators on Windows. Replace the
            # same-length entry name in both the local header and central
            # directory to reproduce the malformed published archive exactly.
            archive_bytes = archive_path.read_bytes().replace(
                posix_name.encode("ascii"), posix_name.replace("/", "\\").encode("ascii")
            )
            archive_path.write_bytes(archive_bytes)

            with self.assertRaisesRegex(ReleaseZipError, "backslashes"):
                validate_release_zip(archive_path)


if __name__ == "__main__":
    unittest.main()
