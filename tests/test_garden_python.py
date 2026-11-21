import runpy
from pathlib import Path
import unittest


LOWER = runpy.run_path(
    str(Path(__file__).resolve().parents[1] / "game/scripts/activities/garden_python.py")
)["lower"]


class GardenPythonTests(unittest.TestCase):
    def test_lowering_preserves_original_source_lines(self):
        result = LOWER("# Start\nfor _ in range(2):\n    hop(east)\n    wait()\n")
        self.assertEqual(result["source"], "repeat 2\nhop east\nwait\nend")
        self.assertEqual(result["lines"], [1, 2, 3, 3])

    def test_compound_conditions_preserve_python_grouping(self):
        result = LOWER("if (lily(north) or ripe()) and not spring():\n    gather()\n")
        self.assertEqual(result["source"], "if lily north and not spring or ripe and not spring\ngather\nend")

    def test_functions_keep_case_and_pass_direction_names(self):
        result = LOWER('def Sweep(Turn):\n    hop(Turn)\nSweep("west")\n')
        self.assertEqual(result["source"], "routine Sweep Turn\nhop Turn\nend\ncall Sweep west")

    def test_planting_uses_the_bed_sensor_and_preserves_existing_routine_names(self):
        self.assertEqual(LOWER("if empty_bed(east):\n    plant()\n")["source"], "if empty_bed east\nplant\nend")
        for routine in ("plant", "empty_bed"):
            with self.subTest(routine=routine):
                source = f"def {routine}():\n    wait()\n{routine}()\n"
                self.assertEqual(LOWER(source)["source"], f"routine {routine}\nwait\nend\ncall {routine}")

    def test_unsupported_syntax_is_rejected_at_its_source_line(self):
        for source, line in [
            ("fill()\nimport math\n", 1),
            ("garden.fill()\n", 0),
            ("for x in range(2):\n    wait()\n", 0),
            ("fill()\nif spring()\n    wait()\n", 1),
        ]:
            with self.subTest(source=source):
                result = LOWER(source)
                self.assertIn("error", result)
                self.assertEqual(result["line"], line)
