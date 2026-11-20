"""Preserve runtime asset timestamps during a setuptools data install."""

from distutils.command.install_data import install_data
from distutils.file_util import copy_file
import os
from pathlib import Path
import stat


def file_version(info):
    return info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns


def same_contents(source, installed):
    with source.open("rb") as left, installed.open("rb") as right:
        while True:
            block = left.read(128 * 1024)
            if block != right.read(128 * 1024):
                return False
            if not block:
                return True


def reuse_rounded_copy(source, installed, source_info, installed_info):
    """Restore precision only for byte-identical, whole-second legacy copies."""
    rounded = source_info.st_mtime_ns // 1_000_000_000 * 1_000_000_000
    if (
        rounded == source_info.st_mtime_ns
        or installed_info.st_mtime_ns != rounded
        or installed_info.st_size != source_info.st_size
        or not stat.S_ISREG(installed_info.st_mode)
    ):
        return False

    try:
        if (
            not same_contents(source, installed)
            or file_version(source.stat()) != file_version(source_info)
            or file_version(installed.lstat()) != file_version(installed_info)
        ):
            return False
    except FileNotFoundError:
        return False
    try:
        os.utime(installed, ns=(installed_info.st_atime_ns, source_info.st_mtime_ns))
    except PermissionError:
        # A read-only legacy copy can still be reused when its bytes match.
        pass
    return True


class AssetInstallData(install_data):
    def copy_file(self, infile, outfile, preserve_mode=1, preserve_times=1, link=None, level=1):
        if self.dry_run or link or not preserve_times:
            return super().copy_file(infile, outfile, preserve_mode, preserve_times, link, level)

        source = Path(infile)
        installed = Path(outfile)
        if installed.is_dir():
            installed /= source.name
        source_info = source.stat()
        try:
            installed_info = installed.lstat()
        except FileNotFoundError:
            installed_info = None
        if installed_info is not None and not self.force:
            if not stat.S_ISREG(installed_info.st_mode):
                return super().copy_file(infile, outfile, preserve_mode, preserve_times, link, level)
            if (
                source_info.st_mtime_ns <= installed_info.st_mtime_ns
                or reuse_rounded_copy(source, installed, source_info, installed_info)
            ):
                return str(installed), False

        # The freshness decision is already made at full timestamp precision.
        # Apply exact times before restoring the source's potentially read-only mode.
        target, copied = copy_file(infile, outfile, preserve_mode=0, preserve_times=0)
        os.utime(target, ns=(source_info.st_atime_ns, source_info.st_mtime_ns))
        if preserve_mode:
            os.chmod(target, stat.S_IMODE(source_info.st_mode))
        return target, copied
