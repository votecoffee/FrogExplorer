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
        self.assertEqual(result["source"], "if\ngather\nend")
        self.assertEqual(result["details"]["0"]["test"], {
            "op": "and", "args": [
                {"op": "or", "args": [
                    {"op": "sensor", "name": "lily", "direction": "north"},
                    {"op": "sensor", "name": "ripe", "direction": ""},
                ]},
                {"op": "not", "args": [{"op": "sensor", "name": "spring", "direction": ""}]},
            ],
        })

    def test_functions_keep_case_and_pass_direction_names(self):
        result = LOWER('def Sweep(Turn):\n    hop(Turn)\nSweep("west")\n')
        self.assertEqual(result["source"], "routine Sweep Turn\nhop Turn\nend\ncall Sweep west")

    def test_planting_uses_the_bed_sensor_and_preserves_existing_routine_names(self):
        result = LOWER("if empty_bed(east):\n    plant()\n")
        self.assertEqual(result["source"], "if\nplant\nend")
        self.assertEqual(result["details"]["0"]["test"], {"op": "sensor", "name": "empty_bed", "direction": "east"})
        for routine in ("plant", "empty_bed"):
            with self.subTest(routine=routine):
                source = f"def {routine}():\n    wait()\n{routine}()\n"
                self.assertEqual(LOWER(source)["source"], f"routine {routine}\nwait\nend\ncall {routine}")

    def test_boolean_literals_support_continuous_programs_and_negation(self):
        source = "while True:\n    if not False and empty_bed():\n        plant()\n"
        result = LOWER(source)
        self.assertEqual(result["source"], "while\nif\nplant\nend\nend")
        self.assertEqual(result["details"]["0"]["test"], {"op": "literal", "value": True})
        self.assertEqual(result["details"]["1"]["test"]["args"][0], {
            "op": "not", "args": [{"op": "literal", "value": False}],
        })

    def test_print_preserves_literals_sensors_and_routine_parameters(self):
        source = r'''def report(Heading):
    print("water # tank\nplant", Heading, empty_bed(Heading), -2.5, True, None)
report("east")
print()
'''
        result = LOWER(source)
        self.assertEqual(result["source"], "routine report Heading\ndiagnostic\nend\ncall report east\ndiagnostic")
        self.assertEqual(result["lines"], [0, 1, 1, 2, 3])
        self.assertEqual(result["details"], {
            "1": {"output": [
                {"op": "text", "value": "water # tank\nplant"}, {"op": "direction", "direction": "Heading"},
                {"op": "sensor", "name": "empty_bed", "direction": "Heading"},
                {"op": "text", "value": "-2.5"}, {"op": "text", "value": "True"}, {"op": "text", "value": "None"},
            ]},
            "4": {"output": []},
        })

    def test_existing_print_routine_remains_callable(self):
        source = "def print():\n    wait()\nprint()\n"
        self.assertEqual(LOWER(source)["source"], "routine print\nwait\nend\ncall print")

    def test_numeric_sensors_lower_chained_and_negated_comparisons(self):
        source = "while 0 < water_level() <= +3 and not (row() < column() <= 2):\n    wait()\n"
        result = LOWER(source)
        self.assertEqual(result["source"], "while\nwait\nend")
        first, second = result["details"]["0"]["test"]["args"]
        self.assertEqual(first["operators"], ["<", "<="])
        self.assertEqual(first["args"], [{"op": "literal", "value": 0},
                                         {"op": "sensor", "name": "water_level", "direction": ""},
                                         {"op": "literal", "value": 3}])
        self.assertEqual(second["op"], "not")
        self.assertEqual(second["args"][0]["operators"], ["<", "<="])
        numeric_test = LOWER("if row():\n    wait()\n")["details"]["0"]["test"]
        self.assertEqual(numeric_test, {"op": "sensor", "name": "row", "direction": ""})

    def test_print_reads_numbers_and_preserves_existing_numeric_sensor_routine_names(self):
        result = LOWER("print(row(), column(), water_level())\n")
        self.assertEqual(result["details"]["0"]["output"], [
            {"op": "sensor", "name": sensor, "direction": ""} for sensor in ("row", "column", "water_level")
        ])
        source = "def row():\n    wait()\nrow()\n"
        self.assertEqual(LOWER(source)["source"], "routine row\nwait\nend\ncall row")

    def test_variables_preserve_case_and_lower_reassignment(self):
        result = LOWER("Start = column()\nStart += 1\nprint(Start - column())\n")
        self.assertEqual(result["source"], "assign\nassign\ndiagnostic")
        self.assertEqual(result["lines"], [0, 1, 2])
        self.assertEqual(result["details"]["0"]["assign"], "Start")
        self.assertEqual(result["details"]["1"], {
            "assign": "Start",
            "value": {"op": "+", "args": [{"op": "variable", "name": "Start"}, {"op": "literal", "value": 1}]},
        })
        self.assertEqual(result["details"]["2"]["output"][0]["op"], "-")

    def test_unsupported_syntax_is_rejected_at_its_source_line(self):
        for source, line in [
            ("fill()\nimport math\n", 1),
            ("garden.fill()\n", 0),
            ("for x in range(2):\n    wait()\n", 0),
            ("fill()\nif spring()\n    wait()\n", 1),
            ("fill()\nprint(plant())\n", 1),
            ("print(has_water(east))\n", 0),
            ("print(1 * 2)\n", 0),
            ("fill()\nif row(east) > 0:\n    wait()\n", 1),
            ("if water_level() is 3:\n    wait()\n", 0),
            ("if water_level() >= 1.5:\n    wait()\n", 0),
            ("if column() > 'east':\n    wait()\n", 0),
            ("if row() < 2147483648:\n    wait()\n", 0),
            ("x = y = 0\n", 0),
            ("water_level = 1\n", 0),
            ("turns = 2\ndef turns():\n    wait()\n", 0),
            ("def survey():\n    if True:\n        position = row()\n", 2),
            ("x = 2\nx *= 3\n", 1),
        ]:
            with self.subTest(source=source):
                result = LOWER(source)
                self.assertIn("error", result)
                self.assertEqual(result["line"], line)
