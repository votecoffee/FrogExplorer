from pathlib import Path
from catkin_pkg.package import parse_package


def test_manifest_is_a_valid_ros_ament_package():
    package=parse_package(str(Path(__file__).resolve().parents[1]/"package.xml"))
    assert package.name=="frog_explorer"
    assert package.get_build_type()=="ament_python"
