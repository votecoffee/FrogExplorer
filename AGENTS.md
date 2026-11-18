# FrogExplorer repository guidance

- Maintain the custom Godot project, ROS package source and build/install tools here. ROS underlays, colcon outputs, tools, original model downloads, captures and personal reports stay outside Git or in ignored local directories.
- Reviewed runtime world tiles and six frog GLBs are published through `config/runtime_assets.lock.json`, including the original MIT red-eyed frog (`red_eye_original.glb`). Preserve existing checksums, source credits and narrow ignore exceptions when adding reviewed assets. Full world GLBs, intermediate glTF/buffers, obsolete tile packs and the historical restricted `red_eye.glb` remain local.
- Work on `main` unless instructed otherwise. Preserve other changes; stage named paths, review diffs, validate cohesive increments and push when publishing is authorized.
- Keep the root README's installation and control tables accurate. Maintain MIT scope separately from optional third-party asset terms.
- Fresh-clone checks: `python -m unittest discover -s tests -v`, `python scripts/repo_check.py`, then installer `-Test` / `--test`. Full world and live ROS suites require their documented optional prerequisites.
- Keep UTF-8 without BOM, LF and one final newline; Windows `.cmd` launchers use CRLF. Commit stable Godot `.gd.uid` files; ignore generated `.import` files and `.godot/`.
- Use injected/headless input for automation. Native hardware, rendered FPS, Linux and Pi acceptance must be identified explicitly.
- Add no automatic GitHub Actions triggers. Any future workflow must be manually dispatched.
