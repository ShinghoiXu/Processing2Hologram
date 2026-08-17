#!/usr/bin/env python3
"""Create and validate the Processing2Hologram release ZIP.

ZIP entry names are archive paths, not host filesystem paths.  This module
therefore constructs every entry from path components with POSIX separators
instead of passing a platform-native Path string to the archive.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path, PurePosixPath
import stat
import tempfile
import time
from typing import NamedTuple
from zipfile import ZIP_DEFLATED, ZIP_STORED, ZipFile, ZipInfo


ARCHIVE_ROOT = "Processing2Hologram"
PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = PROJECT_ROOT / "build" / "releases" / "universal" / ARCHIVE_ROOT
DEFAULT_OUTPUT = PROJECT_ROOT / "build" / f"{ARCHIVE_ROOT}.zip"
REQUIRED_ENTRIES = {
    f"{ARCHIVE_ROOT}/",
    f"{ARCHIVE_ROOT}/examples/",
    f"{ARCHIVE_ROOT}/library/",
    f"{ARCHIVE_ROOT}/library.properties",
    f"{ARCHIVE_ROOT}/library/{ARCHIVE_ROOT}.jar",
}


class ReleaseZipError(RuntimeError):
    """Raised when a distribution or release ZIP violates its contract."""


class ArchiveMember(NamedTuple):
    path: Path
    name: str
    is_directory: bool


class ValidationSummary(NamedTuple):
    entries: int
    files: int
    directories: int
    backslash_entries: int


def _entry_name(relative_path: Path, *, directory: bool) -> str:
    parts = relative_path.parts
    if any(part in {"", ".", ".."} or "\\" in part or "/" in part for part in parts):
        raise ReleaseZipError(f"Unsafe distribution path: {relative_path!s}")

    # PurePosixPath is deliberate: ZIP entry names always use '/', even when
    # the source tree is being traversed on Windows.
    name = PurePosixPath(ARCHIVE_ROOT, *parts).as_posix()
    if directory:
        name += "/"
    return name


def _archive_members(source: Path) -> list[ArchiveMember]:
    if not source.is_dir():
        raise ReleaseZipError(f"Distribution directory does not exist: {source}")
    if source.name != ARCHIVE_ROOT:
        raise ReleaseZipError(
            f"Distribution directory must be named {ARCHIVE_ROOT!r}: {source}"
        )

    members = [ArchiveMember(source, f"{ARCHIVE_ROOT}/", True)]
    paths = sorted(source.rglob("*"), key=lambda path: path.relative_to(source).as_posix())
    for path in paths:
        relative_path = path.relative_to(source)
        if path.is_symlink():
            raise ReleaseZipError(f"Symbolic links are not supported in the release: {path}")
        if path.is_dir():
            members.append(ArchiveMember(path, _entry_name(relative_path, directory=True), True))
        elif path.is_file():
            members.append(ArchiveMember(path, _entry_name(relative_path, directory=False), False))
        else:
            raise ReleaseZipError(f"Unsupported distribution entry: {path}")
    return members


def _directory_info(member: ArchiveMember) -> ZipInfo:
    metadata = member.path.stat()
    modified = time.localtime(metadata.st_mtime)[:6]
    # The ZIP format cannot represent timestamps earlier than 1980.
    if modified[0] < 1980:
        modified = (1980, 1, 1, 0, 0, 0)
    info = ZipInfo(member.name, modified)
    info.create_system = 3
    info.compress_type = ZIP_STORED
    permissions = stat.S_IMODE(metadata.st_mode) or 0o755
    info.external_attr = ((stat.S_IFDIR | permissions) << 16) | 0x10
    return info


def validate_release_zip(archive_path: Path, source: Path | None = None) -> ValidationSummary:
    archive_path = archive_path.resolve()
    if not archive_path.is_file():
        raise ReleaseZipError(f"Release ZIP does not exist: {archive_path}")

    with ZipFile(archive_path, "r") as archive:
        infos = archive.infolist()
        # On Windows, zipfile normalizes '\\' to '/' in ZipInfo.filename while
        # reading. orig_filename preserves the decoded central-directory name
        # and is therefore required to catch the exact release defect.
        names = [info.orig_filename for info in infos]
        bad_crc = archive.testzip()

    errors: list[str] = []
    if bad_crc is not None:
        errors.append(f"CRC validation failed for {bad_crc!r}")
    if len(names) != len(set(names)):
        errors.append("archive contains duplicate entry names")

    backslash_names = [name for name in names if "\\" in name]
    if backslash_names:
        errors.append(f"entry names contain backslashes: {backslash_names[0]!r}")

    for name in names:
        if not name or name.startswith("/"):
            errors.append(f"entry name is not relative: {name!r}")
            continue
        parts = name.rstrip("/").split("/")
        if any(part in {"", ".", ".."} for part in parts):
            errors.append(f"entry name contains an unsafe component: {name!r}")

    name_set = set(names)
    missing_required = sorted(REQUIRED_ENTRIES - name_set)
    if missing_required:
        errors.append(f"archive is missing required entries: {missing_required!r}")

    top_levels = {name.rstrip("/").split("/", 1)[0] for name in names if name}
    if top_levels != {ARCHIVE_ROOT}:
        errors.append(f"archive must have one {ARCHIVE_ROOT!r} top-level folder: {top_levels!r}")

    # Every parent is required to exist as an explicit, slash-terminated
    # directory entry, including the archive's top-level library folder.
    for name in names:
        parts = name.rstrip("/").split("/")
        for index in range(1, len(parts)):
            parent = "/".join(parts[:index]) + "/"
            if parent not in name_set:
                errors.append(f"entry {name!r} has no explicit parent directory {parent!r}")
                break

    if source is not None:
        expected_names = {member.name for member in _archive_members(source.resolve())}
        missing = sorted(expected_names - name_set)
        unexpected = sorted(name_set - expected_names)
        if missing:
            errors.append(f"archive omitted distribution entries: {missing!r}")
        if unexpected:
            errors.append(f"archive contains unexpected entries: {unexpected!r}")

    if errors:
        raise ReleaseZipError("Invalid release ZIP: " + "; ".join(errors))

    directories = sum(info.is_dir() for info in infos)
    return ValidationSummary(
        entries=len(infos),
        files=len(infos) - directories,
        directories=directories,
        backslash_entries=len(backslash_names),
    )


def create_release_zip(source: Path, output: Path) -> ValidationSummary:
    source = source.resolve()
    output = output.resolve()
    members = _archive_members(source)

    try:
        output.relative_to(source)
    except ValueError:
        pass
    else:
        raise ReleaseZipError(f"Release ZIP cannot be written inside its source tree: {output}")

    output.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{output.name}.", suffix=".tmp", dir=output.parent
    )
    os.close(descriptor)
    temporary_path = Path(temporary_name)
    try:
        with ZipFile(temporary_path, "w", compression=ZIP_DEFLATED, compresslevel=9) as archive:
            for member in members:
                if member.is_directory:
                    archive.writestr(_directory_info(member), b"")
                else:
                    archive.write(
                        member.path,
                        arcname=member.name,
                        compress_type=ZIP_DEFLATED,
                        compresslevel=9,
                    )

        summary = validate_release_zip(temporary_path, source)
        os.replace(temporary_path, output)
        return summary
    finally:
        temporary_path.unlink(missing_ok=True)


def _print_summary(action: str, archive_path: Path, summary: ValidationSummary) -> None:
    print(f"{action}: {archive_path.resolve()}")
    print(
        f"Entries: {summary.entries} "
        f"({summary.directories} directories, {summary.files} files); "
        f"backslash entries: {summary.backslash_entries}"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        type=Path,
        default=DEFAULT_SOURCE,
        help=f"distribution folder (default: {DEFAULT_SOURCE})",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f"output ZIP (default: {DEFAULT_OUTPUT})",
    )
    parser.add_argument(
        "--verify",
        type=Path,
        metavar="ZIP",
        help="validate an existing ZIP instead of creating one",
    )
    args = parser.parse_args()

    try:
        if args.verify is not None:
            summary = validate_release_zip(args.verify)
            _print_summary("Validated release ZIP", args.verify, summary)
        else:
            summary = create_release_zip(args.source, args.output)
            _print_summary("Created release ZIP", args.output, summary)
    except (OSError, ReleaseZipError) as error:
        parser.exit(1, f"error: {error}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
