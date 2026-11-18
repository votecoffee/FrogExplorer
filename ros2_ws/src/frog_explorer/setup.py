from pathlib import Path
import os
from setuptools import setup
from frog_explorer.asset_files import game_files

project = Path(__file__).resolve().parents[3]
game = project / "game"
data = [("share/ament_index/resource_index/packages", ["resource/frog_explorer"]),
        ("share/frog_explorer", ["package.xml"]),
        ("share/frog_explorer/launch", ["launch/explorer.launch.py"])]
data.append(("share/frog_explorer",[os.path.relpath(project/name,Path(__file__).resolve().parent) for name in ["README.md","LICENSE","ASSET_CREDITS.md"]]))
runtime_files=game_files(game)
runtime_folders={}
for path in runtime_files:
    runtime_folders.setdefault(path.parent,[]).append(os.path.relpath(path,Path(__file__).resolve().parent))
for folder,files in sorted(runtime_folders.items()):
    data.append((str(Path("share/frog_explorer/game") / folder.relative_to(game)), files))
setup(name="frog_explorer", version="0.1.0", packages=["frog_explorer"],
      data_files=data, install_requires=["setuptools"], zip_safe=False,
      maintainer="votecoffee", maintainer_email="7451299+votecoffee@users.noreply.github.com",
      description="Woodland pond exploration game and ROS 2 bridge", license="MIT",
      tests_require=["pytest"], entry_points={"console_scripts": ["game_bridge=frog_explorer.bridge:main"]})
