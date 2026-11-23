"""Read Python source and lower its garden statements without executing the source."""

import ast
import json
from pathlib import Path
import sys


ACTIONS = {"fill", "hop", "plant", "water", "wait", "gather"}
SENSORS = {"clear", "spring", "has_water", "empty_bed", "lily", "thirsty", "growing", "ripe", "has_reach_tool", "has_harvest_hook"}
NUMERIC_SENSORS = {"water_level", "tank_capacity", "row", "column", "harvest_count", "action_count"}
COMPARISONS = {ast.Lt: "<", ast.LtE: "<=", ast.Eq: "==", ast.NotEq: "!=", ast.GtE: ">=", ast.Gt: ">"}
DIRECTIONS = {"north", "east", "south", "west"}
# Preserve names available to older drafts before these commands and readings were added.
RESERVED_NAMES = (ACTIONS | SENSORS | DIRECTIONS | {"range"}) - {"plant", "empty_bed", "has_reach_tool", "has_harvest_hook"}
VARIABLE_RESERVED_NAMES = (ACTIONS | SENSORS | NUMERIC_SENSORS | DIRECTIONS | {"print", "range", "_"}) - {
    "tank_capacity", "has_reach_tool", "has_harvest_hook", "harvest_count", "action_count",
}
VALUE_TYPES = {"int", "bool"}
MAX_SOURCE = 8192
MIN_VALUE = -(2 ** 31)
MAX_VALUE = 2 ** 31 - 1


class GardenError(Exception):
    def __init__(self, node, message):
        super().__init__(message)
        self.line = node.lineno - 1


def name(token, node):
    if not token.isascii():
        raise GardenError(node, "Use ASCII letters, digits, and underscores in garden names.")
    return token


def variable_name(node, routine_names):
    token = name(node.id, node)
    if token in VARIABLE_RESERVED_NAMES or token in routine_names:
        raise GardenError(node, "Choose a variable name distinct from garden commands and functions.")
    return token


def arguments(node):
    if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Name) or node.keywords:
        raise GardenError(node, "Call a garden function by name with positional arguments.")
    return name(node.func.id, node), node.args


def direction(node):
    if isinstance(node, ast.Name):
        return name(node.id, node)
    if isinstance(node, ast.Constant) and isinstance(node.value, str) and node.value in DIRECTIONS:
        return node.value
    raise GardenError(node, "Use a compass direction such as east, or a direction parameter.")


def sensor_call(node):
    sensor, args = arguments(node)
    if sensor not in SENSORS | NUMERIC_SENSORS:
        raise GardenError(node, "Use a garden test such as empty_bed(north) or has_water().")
    if sensor in NUMERIC_SENSORS and args:
        raise GardenError(node, f"Use {sensor}() without arguments.")
    if len(args) > 1 or (sensor == "clear" and not args) or (sensor in {"has_water", "has_reach_tool", "has_harvest_hook"} and args):
        raise GardenError(node, "Check the direction arguments for this garden test.")
    return sensor, direction(args[0]) if args else ""


def expression(node, routines, parameters, local_names, depth=0):
    if depth >= 64:
        raise GardenError(node, "Split this expression into smaller expressions.")

    def child(value):
        return expression(value, routines, parameters, local_names, depth + 1)

    if isinstance(node, ast.Name):
        variable = name(node.id, node)
        if variable in parameters or variable in VARIABLE_RESERVED_NAMES:
            raise GardenError(node, "Use a variable or call a reading such as row().")
        result = {"op": "variable", "name": variable}
        if variable in local_names:
            result["local"] = True
        return result
    if isinstance(node, ast.Call):
        if isinstance(node.func, ast.Name) and node.func.id in routines:
            raise GardenError(node, "Assign the function result to a variable before using it here.")
        sensor, target = sensor_call(node)
        if target and target not in DIRECTIONS and target not in parameters:
            raise GardenError(node, "Use a compass direction or a direction parameter.")
        return {"op": "sensor", "name": sensor, "direction": target}
    if isinstance(node, ast.BoolOp):
        op = "and" if isinstance(node.op, ast.And) else "or"
        return {"op": op, "args": [child(value) for value in node.values]}
    if isinstance(node, ast.Compare):
        if any(type(op) not in COMPARISONS for op in node.ops):
            raise GardenError(node, "Use <, <=, ==, !=, >=, or > to compare readings or whole numbers.")
        return {"op": "compare", "operators": [COMPARISONS[type(op)] for op in node.ops],
                "args": [child(node.left), *(child(value) for value in node.comparators)]}
    if isinstance(node, ast.BinOp) and isinstance(node.op, (ast.Add, ast.Sub)):
        op = "+" if isinstance(node.op, ast.Add) else "-"
        return {"op": op, "args": [child(node.left), child(node.right)]}
    if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.Not):
        return {"op": "not", "args": [child(node.operand)]}
    if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.UAdd, ast.USub)):
        if not isinstance(node.operand, ast.Constant) or type(node.operand.value) not in (bool, int):
            op = "+" if isinstance(node.op, ast.UAdd) else "-"
            return {"op": op, "args": [{"op": "literal", "value": 0}, child(node.operand)]}
        value = int(node.operand.value) * (-1 if isinstance(node.op, ast.USub) else 1)
    elif isinstance(node, ast.Constant) and type(node.value) in (bool, int):
        value = node.value
    else:
        raise GardenError(node, "Use a whole number, True, False, a variable, or a garden reading.")
    if not MIN_VALUE <= value <= MAX_VALUE:
        raise GardenError(node, "Use a 32-bit integer in expressions.")
    return {"op": "literal", "value": value}


def print_value(node, routines, parameters, local_names):
    if isinstance(node, ast.Name) and (node.id in DIRECTIONS or node.id in parameters):
        return {"op": "direction", "direction": direction(node)}
    if isinstance(node, ast.Constant) and type(node.value) in (str, bool, int, float, type(None)):
        value = node.value
    elif (isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.UAdd, ast.USub)) and
          isinstance(node.operand, ast.Constant) and type(node.operand.value) in (int, float)):
        value = -node.operand.value if isinstance(node.op, ast.USub) else node.operand.value
    else:
        return expression(node, routines, parameters, local_names)
    try:
        value = str(value).encode("utf-8", errors="replace").decode("utf-8").replace("\0", "\u2400")
        return {"op": "text", "value": value}
    except ValueError:
        raise GardenError(node, "Use a smaller number in print().") from None


def lower(source):
    lines = []
    locations = []
    routines = {}
    details = {}

    def emit(text, line):
        lines.append(text)
        locations.append(line - 1)

    def block(statements, parameters, local_names):
        def lower_value(node):
            return expression(node, routines, parameters, local_names)

        def emit_call(command, args, line, capture=None):
            kinds = routines.get(command, [])
            words = ["call", command]
            value_args = {}
            for index, arg in enumerate(args):
                if index < len(kinds) and kinds[index] in VALUE_TYPES:
                    # Keep one word per positional argument for the direction binder.
                    words.append("_")
                    value_args[str(index)] = lower_value(arg)
                else:
                    words.append(direction(arg))
            detail = {}
            if value_args:
                detail["value_args"] = value_args
            if capture is not None:
                detail["capture"] = capture
            if detail:
                details[str(len(lines))] = detail
            emit(" ".join(words), line)

        def target_name(node):
            token = variable_name(node, routine_names)
            if token in parameters:
                raise GardenError(node, "Choose a variable name distinct from direction parameters.")
            return token

        for node in statements:
            if isinstance(node, ast.Expr):
                command, args = arguments(node.value)
                if command == "print" and command not in routines:
                    details[str(len(lines))] = {
                        "output": [print_value(arg, routines, parameters, local_names) for arg in args],
                    }
                    emit("diagnostic", node.lineno)
                    continue
                if command in ACTIONS and command not in routines:
                    counts = (0, 1) if command in {"plant", "water", "gather"} else (int(command == "hop"),)
                    if len(args) not in counts:
                        raise GardenError(node, f"Check the arguments for {command}().")
                    emit(" ".join([command, *(direction(arg) for arg in args)]), node.lineno)
                else:
                    emit_call(command, args, node.lineno)
            elif isinstance(node, (ast.Assign, ast.AugAssign)):
                targets = node.targets if isinstance(node, ast.Assign) else [node.target]
                if len(targets) != 1 or not isinstance(targets[0], ast.Name):
                    raise GardenError(node, "Assign one variable at a time, such as visits = 0.")
                token = target_name(targets[0])
                value = node.value
                if isinstance(node, ast.Assign) and isinstance(value, ast.Call) and isinstance(value.func, ast.Name):
                    called = value.func.id
                    if called in routines or called in routine_names - SENSORS - NUMERIC_SENSORS:
                        command, args = arguments(value)
                        emit_call(command, args, node.lineno, {"name": token, "local": token in local_names})
                        continue
                if isinstance(node, ast.AugAssign):
                    value = ast.copy_location(ast.BinOp(targets[0], node.op, value), node)
                assignment = {"assign": token, "value": lower_value(value)}
                if token in local_names:
                    assignment["local"] = True
                details[str(len(lines))] = assignment
                emit("assign", node.lineno)
            elif isinstance(node, ast.FunctionDef):
                args = node.args
                if (node.decorator_list or node.returns or getattr(node, "type_params", []) or
                    args.posonlyargs or args.vararg or args.kwonlyargs or args.kwarg or args.defaults):
                    raise GardenError(node, "Use a simple def with positional parameters.")
                routine = name(node.name, node)
                if routine in RESERVED_NAMES:
                    raise GardenError(node, "Choose a different name for this garden function.")
                names = [name(arg.arg, arg) for arg in args.args]
                value_parameters = {}
                for arg, token in zip(args.args, names):
                    if arg.annotation is None:
                        continue
                    if not isinstance(arg.annotation, ast.Name) or arg.annotation.id not in VALUE_TYPES:
                        raise GardenError(arg, "Use int or bool for value parameters. Leave directions unannotated.")
                    if token in VARIABLE_RESERVED_NAMES or token in routine_names:
                        raise GardenError(arg, "Choose a parameter name distinct from garden commands and functions.")
                    value_parameters[token] = arg.annotation.id
                routines[routine] = [value_parameters.get(token, "direction") for token in names]
                # A name assigned anywhere in a function is local throughout that function.
                assigned = {item.id for item in ast.walk(node) if isinstance(item, ast.Name)
                            and isinstance(item.ctx, ast.Store) and item.id != "_"}
                assigned.update(value_parameters)
                if assigned:
                    details[str(len(lines))] = {"local_scope": True}
                if value_parameters:
                    details[str(len(lines))]["value_parameters"] = value_parameters
                emit(" ".join(["routine", routine, *names]), node.lineno)
                block(node.body, set(names) - value_parameters.keys(), assigned)
                emit("end", node.end_lineno)
            elif isinstance(node, (ast.If, ast.While)):
                keyword = "if" if isinstance(node, ast.If) else "while"
                if keyword == "while" and node.orelse:
                    raise GardenError(node, "Use else with if in the garden.")
                details[str(len(lines))] = {"test": lower_value(node.test)}
                emit(keyword, node.lineno)
                block(node.body, parameters, local_names)
                if node.orelse:
                    emit("else", node.orelse[0].lineno)
                    block(node.orelse, parameters, local_names)
                emit("end", node.end_lineno)
            elif isinstance(node, ast.For):
                iterator, args = arguments(node.iter)
                if iterator != "range" or not isinstance(node.target, ast.Name) or not 1 <= len(args) <= 3:
                    raise GardenError(node, "Use for index in range(stop) or range(start, stop, step).")
                if node.orelse:
                    raise GardenError(node, "Use else with if in the garden.")
                target = "" if node.target.id == "_" else target_name(node.target)
                bounds = {"target": target, "args": [lower_value(arg) for arg in args]}
                if target in local_names:
                    bounds["local"] = True
                details[str(len(lines))] = {"range": bounds}
                emit("for", node.lineno)
                block(node.body, parameters, local_names)
                emit("end", node.end_lineno)
            elif isinstance(node, (ast.Break, ast.Continue)):
                emit(type(node).__name__.lower(), node.lineno)
            elif isinstance(node, ast.Return):
                result = {"return": True}
                if node.value is not None and not (isinstance(node.value, ast.Constant) and node.value.value is None):
                    result["value"] = lower_value(node.value)
                details[str(len(lines))] = result
                emit("return", node.lineno)
            else:
                raise GardenError(node, "Use garden calls, assignments, def, if, while, for, break, continue, or return.")

    if len(source) > MAX_SOURCE:
        return {"error": "Programs can contain up to 8,192 characters.", "line": 0}
    try:
        tree = ast.parse(source, feature_version=(3, 10))
        routine_names = {node.name for node in tree.body if isinstance(node, ast.FunctionDef)}
        block(tree.body, set(), set())
    except SyntaxError as error:
        return {"error": error.msg, "line": max(0, (error.lineno or 1) - 1)}
    except GardenError as error:
        return {"error": str(error), "line": error.line}
    except RecursionError:
        return {"error": "Split this program into smaller expressions.", "line": 0}
    result = {"source": "\n".join(lines), "lines": locations}
    if details:
        result["details"] = details
    return result


if __name__ == "__main__":
    if sys.version_info < (3, 10):
        print(json.dumps({"error": "Lily Code Garden requires Python 3.10 or newer.", "line": 0}))
    else:
        print(json.dumps(lower(Path(sys.argv[1]).read_text(encoding="utf-8"))))
