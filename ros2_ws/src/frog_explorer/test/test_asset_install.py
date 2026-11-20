import os

import pytest
from setuptools import Distribution

from frog_explorer.asset_install import AssetInstallData


STAMP = 1_700_000_001_375_000_000
ROUNDED = 1_700_000_001_000_000_000


@pytest.fixture
def asset_pair(tmp_path):
    source = tmp_path / "tile.jpg"
    source.write_bytes(b"updated tile")
    os.utime(source, ns=(STAMP, STAMP))
    if source.stat().st_mtime_ns != STAMP:
        pytest.skip("the fixture requires subsecond file timestamps")
    installed = tmp_path / "installed"
    installed.mkdir()
    return source, installed / source.name


def test_copied_asset_keeps_subsecond_timestamp_and_is_skipped_next_time(asset_pair):
    source, installed = asset_pair
    command = AssetInstallData(Distribution())
    target, copied = command.copy_file(str(source), str(installed.parent))
    assert copied and target == str(installed)
    assert installed.stat().st_mtime_ns == source.stat().st_mtime_ns
    assert command.copy_file(str(source), str(installed.parent)) == (str(installed), False)


def test_rounded_identical_asset_is_reused(asset_pair):
    source, installed = asset_pair
    installed.write_bytes(source.read_bytes())
    os.utime(installed, ns=(ROUNDED, ROUNDED))
    command = AssetInstallData(Distribution())
    assert command.copy_file(str(source), str(installed.parent)) == (str(installed), False)
    assert installed.stat().st_mtime_ns == source.stat().st_mtime_ns


def test_rounded_different_asset_is_copied_even_at_the_same_size(asset_pair):
    source, installed = asset_pair
    installed.write_bytes(b"previous jpg")
    assert installed.stat().st_size == source.stat().st_size
    os.utime(installed, ns=(ROUNDED, ROUNDED))
    command = AssetInstallData(Distribution())
    assert command.copy_file(str(source), str(installed.parent)) == (str(installed), True)
    assert installed.read_bytes() == source.read_bytes()
    assert installed.stat().st_mtime_ns == source.stat().st_mtime_ns


def test_force_copies_identical_assets(asset_pair):
    source, installed = asset_pair
    installed.write_bytes(source.read_bytes())
    os.utime(installed, ns=(STAMP, STAMP))
    command = AssetInstallData(Distribution())
    command.force = True
    assert command.copy_file(str(source), str(installed.parent)) == (str(installed), True)


def test_newer_subsecond_revision_replaces_precisely_stamped_asset(asset_pair):
    source, installed = asset_pair
    command = AssetInstallData(Distribution())
    command.copy_file(str(source), str(installed.parent))
    source.write_bytes(b"fresher tile")
    os.utime(source, ns=(STAMP + 100_000_000, STAMP + 100_000_000))

    assert command.copy_file(str(source), str(installed.parent)) == (str(installed), True)
    assert installed.read_bytes() == source.read_bytes()
    assert installed.stat().st_mtime_ns == source.stat().st_mtime_ns
