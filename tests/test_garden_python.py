import runpy
from pathlib import Path
import unittest


LOWER = runpy.run_path(
    str(Path(__file__).resolve().parents[1] / "game/scripts/activities/garden_python.py")
)["lower"]


class GardenPythonTests(unittest.TestCase):
    def test_lowering_preserves_original_source_lines(self):
        result = LOWER("# Start\nfor _ in range(2):\n    hop(east)\n    wait()\n")
        self.assertEqual(result["source"], "for\nhop east\nwait\nend")
        self.assertEqual(result["lines"], [1, 2, 3, 3])
        self.assertEqual(result["details"]["0"]["range"], {
            "target": "", "args": [{"op": "literal", "value": 2}],
        })

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

    def test_range_preserves_named_index_and_orders_bound_expressions(self):
        result = LOWER("Limit = column()\nfor Step in range(Limit, -1, -2):\n    print(Step)\n")
        self.assertEqual(result["source"], "assign\nfor\ndiagnostic\nend")
        self.assertEqual(result["details"]["1"]["range"], {
            "target": "Step",
            "args": [{"op": "variable", "name": "Limit"}, {"op": "literal", "value": -1},
                     {"op": "literal", "value": -2}],
        })
        self.assertEqual(result["details"]["2"]["output"], [{"op": "variable", "name": "Step"}])

    def test_range_bounds_can_use_routine_direction_arguments(self):
        result = LOWER("def travel(Heading):\n    for _ in range(clear(Heading)):\n        hop(Heading)\ntravel(east)\n")
        self.assertEqual(result["source"], "routine travel Heading\nfor\nhop Heading\nend\nend\ncall travel east")
        self.assertEqual(result["details"]["1"]["range"]["args"], [
            {"op": "sensor", "name": "clear", "direction": "Heading"},
        ])

    def test_function_assignments_mark_local_reads_before_assignment(self):
        result = LOWER("def survey():\n    print(Start)\n    if True:\n        Start = row()\nsurvey()\n")
        self.assertEqual(result["details"]["0"], {"local_scope": True})
        self.assertEqual(result["details"]["1"]["output"], [
            {"op": "variable", "name": "Start", "local": True},
        ])
        self.assertEqual(result["details"]["3"], {
            "assign": "Start", "local": True, "value": {"op": "sensor", "name": "row", "direction": ""},
        })

    def test_function_range_target_is_local_but_unassigned_names_stay_global(self):
        result = LOWER("def trip():\n    for step in range(limit):\n        print(step, limit)\ntrip()\n")
        self.assertEqual(result["details"]["1"]["range"], {
            "target": "step", "local": True, "args": [{"op": "variable", "name": "limit"}],
        })
        self.assertEqual(result["details"]["2"]["output"], [
            {"op": "variable", "name": "step", "local": True}, {"op": "variable", "name": "limit"},
        ])

    def test_bare_return_and_return_none_keep_their_source_lines(self):
        result = LOWER("def sweep():\n    if not clear(east):\n        return\n    hop(east)\n    return None\nsweep()\n")
        self.assertEqual(result["source"], "routine sweep\nif\nreturn\nend\nhop east\nreturn\nend\ncall sweep")
        self.assertEqual(result["lines"], [0, 1, 2, 2, 3, 4, 4, 5])
        self.assertEqual(result["details"]["2"], {"return": True})
        self.assertEqual(result["details"]["5"], {"return": True})

    def test_function_results_lower_to_calls_with_a_local_or_module_destination(self):
        result = LOWER("def reading(Heading):\n    return clear(Heading)\ndef survey(Heading):\n"
                       "    ready = reading(Heading)\n    return ready\nseen = survey(north)\n")
        self.assertEqual(result["source"], "routine reading Heading\nreturn\nend\nroutine survey Heading\n"
                         "call reading Heading\nreturn\nend\ncall survey north")
        self.assertEqual(result["details"]["1"], {
            "return": True, "value": {"op": "sensor", "name": "clear", "direction": "Heading"},
        })
        self.assertEqual(result["details"]["4"], {"capture": {"name": "ready", "local": True}})
        self.assertEqual(result["details"]["5"], {
            "return": True, "value": {"op": "variable", "name": "ready", "local": True},
        })
        self.assertEqual(result["details"]["7"], {"capture": {"name": "seen", "local": False}})

    def test_typed_value_arguments_keep_their_positions_among_directions(self):
        source = ("def report(Count: int, Heading, ready: bool):\n"
                  "    print(Count, Heading, ready)\nreport(column() + 1, east, spring())\n")
        result = LOWER(source)
        self.assertEqual(result["source"], "routine report Count Heading ready\ndiagnostic\nend\ncall report _ east _")
        self.assertEqual(result["details"]["0"], {
            "local_scope": True, "value_parameters": {"Count": "int", "ready": "bool"},
        })
        self.assertEqual(result["details"]["1"]["output"], [
            {"op": "variable", "name": "Count", "local": True},
            {"op": "direction", "direction": "Heading"},
            {"op": "variable", "name": "ready", "local": True},
        ])
        self.assertEqual(result["details"]["3"]["value_args"], {
            "0": {"op": "+", "args": [{"op": "sensor", "name": "column", "direction": ""},
                                      {"op": "literal", "value": 1}]},
            "2": {"op": "sensor", "name": "spring", "direction": ""},
        })

    def test_tank_capacity_reading_preserves_an_existing_variable_name(self):
        result = LOWER("tank_capacity = 4\nprint(tank_capacity, tank_capacity())\n")
        self.assertEqual(result["source"], "assign\ndiagnostic")
        self.assertEqual(result["details"]["1"]["output"], [
            {"op": "variable", "name": "tank_capacity"},
            {"op": "sensor", "name": "tank_capacity", "direction": ""},
        ])

    def test_reach_commands_lower_direction_parameters_and_tool_readings(self):
        result = LOWER("def tend(Heading):\n    plant(Heading)\n    water(Heading)\ntend(east)\nprint(has_reach_tool())\n")
        self.assertEqual(result["source"], "routine tend Heading\nplant Heading\nwater Heading\nend\n"
                         "call tend east\ndiagnostic")
        self.assertEqual(result["details"]["5"]["output"], [
            {"op": "sensor", "name": "has_reach_tool", "direction": ""},
        ])
        old_draft = "def has_reach_tool():\n    wait()\nhas_reach_tool()\n"
        self.assertEqual(LOWER(old_draft)["source"], "routine has_reach_tool\nwait\nend\ncall has_reach_tool")

    def test_harvest_hook_lowers_directional_gather_and_preserves_existing_names(self):
        result = LOWER("def collect(heading):\n    gather(heading)\ncollect(north)\ngather()\n"
                       "print(has_harvest_hook())\n")
        self.assertEqual(result["source"], "routine collect heading\ngather heading\nend\n"
                         "call collect north\ngather\ndiagnostic")
        self.assertEqual(result["details"]["5"]["output"], [
            {"op": "sensor", "name": "has_harvest_hook", "direction": ""},
        ])
        old_draft = "def has_harvest_hook():\n    wait()\nhas_harvest_hook()\n"
        self.assertEqual(LOWER(old_draft)["source"], "routine has_harvest_hook\nwait\nend\ncall has_harvest_hook")

    def test_run_counters_lower_numeric_readings_and_preserve_older_drafts(self):
        result = LOWER("harvest_count = 4\naction_count = 7\n"
                       "print(harvest_count, action_count, harvest_count(), action_count())\n")
        self.assertEqual(result["source"], "assign\nassign\ndiagnostic")
        self.assertEqual(result["details"]["2"]["output"], [
            {"op": "variable", "name": "harvest_count"},
            {"op": "variable", "name": "action_count"},
            {"op": "sensor", "name": "harvest_count", "direction": ""},
            {"op": "sensor", "name": "action_count", "direction": ""},
        ])
        for counter in ("harvest_count", "action_count"):
            with self.subTest(counter=counter):
                old_draft = f"def {counter}():\n    wait()\n{counter}()\n"
                self.assertEqual(LOWER(old_draft)["source"], f"routine {counter}\nwait\nend\ncall {counter}")

    def test_unsupported_syntax_is_rejected_at_its_source_line(self):
        for source, line in [
            ("fill()\nimport math\n", 1),
            ("garden.fill()\n", 0),
            ("for x in range():\n    wait()\n", 0),
            ("for x in range(1, 2, 3, 4):\n    wait()\n", 0),
            ("for a, b in range(2):\n    wait()\n", 0),
            ("for water_level in range(2):\n    wait()\n", 0),
            ("def trip(heading):\n    for heading in range(2):\n        wait()\n", 1),
            ("for step in range(2):\n    wait()\nelse:\n    wait()\n", 0),
            ("fill()\nif spring()\n    wait()\n", 1),
            ("fill()\nprint(plant())\n", 1),
            ("print(has_water(east))\n", 0),
            ("print(has_reach_tool(east))\n", 0),
            ("print(has_harvest_hook(east))\n", 0),
            ("gather(north, east)\n", 0),
            ("print(harvest_count(east))\n", 0),
            ("print(action_count(1))\n", 0),
            ("plant(north, east)\n", 0),
            ("print(1 * 2)\n", 0),
            ("fill()\nif row(east) > 0:\n    wait()\n", 1),
            ("if water_level() is 3:\n    wait()\n", 0),
            ("if water_level() >= 1.5:\n    wait()\n", 0),
            ("if column() > 'east':\n    wait()\n", 0),
            ("if row() < 2147483648:\n    wait()\n", 0),
            ("x = y = 0\n", 0),
            ("water_level = 1\n", 0),
            ("turns = 2\ndef turns():\n    wait()\n", 0),
            ("def survey(heading):\n    heading = row()\n", 1),
            ("def survey(heading: str):\n    hop(heading)\n", 0),
            ("def survey(water_level: int):\n    wait()\n", 0),
            ("def survey():\n    global position\n", 1),
            ("def survey():\n    return 'east'\n", 1),
            ("def survey():\n    return 1\nprint(survey())\n", 2),
            ("x = 2\nx *= 3\n", 1),
        ]:
            with self.subTest(source=source):
                result = LOWER(source)
                self.assertIn("error", result)
                self.assertEqual(result["line"], line)
