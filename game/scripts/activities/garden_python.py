"""Read Python source and lower its garden statements without executing the source."""

import ast
import json
from pathlib import Path
import sys


ACTIONS = {"fill", "hop", "plant", "water", "wait", "gather"}
SENSORS = {"clear", "spring", "has_water", "empty_bed", "lily", "thirsty", "growing", "ripe"}
NUMERIC_SENSORS = {"water_level", "row", "column"}
COMPARISONS = {ast.Lt: "<", ast.LtE: "<=", ast.Eq: "==", ast.NotEq: "!=", ast.GtE: ">=", ast.Gt: ">"}
DIRECTIONS = {"north", "east", "south", "west"}
# Older Python drafts could define these two names as routines.
RESERVED_NAMES = (ACTIONS | SENSORS | DIRECTIONS | {"range"}) - {"plant", "empty_bed"}
MAX_SOURCE = 8192


class GardenError(Exception):
    def __init__(self, node, message):
        super().__init__(message)
        self.line = node.lineno - 1


def name(token, node):
    if not token.isascii():
        raise GardenError(node, "Use ASCII letters, digits, and underscores in garden names.")
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


def sensor_call(node, routines):
    sensor, args = arguments(node)
    if sensor not in SENSORS | NUMERIC_SENSORS or sensor in routines:
        raise GardenError(node, "Use a garden test such as empty_bed(north) or has_water().")
    if sensor in NUMERIC_SENSORS and args:
        raise GardenError(node, f"Use {sensor}() without arguments.")
    if len(args) > 1 or (sensor == "clear" and not args) or (sensor == "has_water" and args):
        raise GardenError(node, "Check the direction arguments for this garden test.")
    return sensor, direction(args[0]) if args else ""


def numeric_operand(node, routines):
    if isinstance(node, ast.Call):
        sensor, _ = sensor_call(node, routines)
        if sensor in NUMERIC_SENSORS:
            return sensor
    sign = 1
    if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.UAdd, ast.USub)):
        sign = -1 if isinstance(node.op, ast.USub) else 1
        node = node.operand
    if isinstance(node, ast.Constant) and type(node.value) is int:
        value = sign * node.value
        if -(2 ** 31) <= value < 2 ** 31:
            return str(value)
        raise GardenError(node, "Use a 32-bit integer in a comparison.")
    raise GardenError(node, "Compare whole numbers and readings such as water_level(), row(), or column().")


def print_value(node, routines):
    if isinstance(node, ast.Call):
        sensor, target = sensor_call(node, routines)
        return {"sensor": sensor, "direction": target}
    if isinstance(node, ast.Name):
        return {"direction": direction(node)}
    if isinstance(node, ast.Constant) and type(node.value) in (str, bool, int, float, type(None)):
        value = node.value
    elif (isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.UAdd, ast.USub)) and
          isinstance(node.operand, ast.Constant) and type(node.operand.value) in (int, float)):
        value = -node.operand.value if isinstance(node.op, ast.USub) else node.operand.value
    else:
        raise GardenError(node, "Use text, a number, a direction, or a garden test in print().")
    try:
        return {"text": str(value).encode("utf-8", errors="replace").decode("utf-8").replace("\0", "\u2400")}
    except ValueError:
        raise GardenError(node, "Use a smaller number in print().") from None


def clauses(node, routines, inverted=False):
    if isinstance(node, ast.Constant) and type(node.value) is bool:
        return [["always" if node.value != inverted else "not always"]]
    if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.Not):
        return clauses(node.operand, routines, not inverted)
    if isinstance(node, ast.Compare):
        if len(node.ops) > 64:
            raise GardenError(node, "Split this test into smaller conditions.")
        if any(type(op) not in COMPARISONS for op in node.ops):
            raise GardenError(node, "Use <, <=, ==, !=, >=, or > to compare numbers.")
        operands = [numeric_operand(value, routines) for value in [node.left, *node.comparators]]
        tests = [f"{left} {COMPARISONS[type(op)]} {right}"
                 for left, op, right in zip(operands, node.ops, operands[1:])]
        return [[f"not {term}"] for term in tests] if inverted else [tests]
    if isinstance(node, ast.BoolOp):
        join = isinstance(node.op, ast.And) != inverted
        result = [[]] if join else []
        for value in node.values:
            terms = clauses(value, routines, inverted)
            if join:
                if len(result) * len(terms) > 64:
                    raise GardenError(node, "Split this test into smaller conditions.")
                result = [left + right for left in result for right in terms]
            else:
                result.extend(terms)
                if len(result) > 64:
                    raise GardenError(node, "Split this test into smaller conditions.")
            if sum(map(len, result)) > 256:
                raise GardenError(node, "Split this test into smaller conditions.")
        return result
    sensor, target = sensor_call(node, routines)
    if sensor in NUMERIC_SENSORS:
        term = f"{sensor} != 0"
    else:
        term = f"{sensor} {target}" if target else sensor
    return [[f"not {term}" if inverted else term]]


def lower(source):
    lines = []
    locations = []
    routines = set()
    diagnostics = {}

    def emit(text, line):
        lines.append(text)
        locations.append(line - 1)

    def block(statements):
        for node in statements:
            if isinstance(node, ast.Expr):
                command, args = arguments(node.value)
                if command == "print" and command not in routines:
                    diagnostics[str(len(lines))] = [print_value(arg, routines) for arg in args]
                    emit("diagnostic", node.lineno)
                    continue
                if command in ACTIONS and command not in routines:
                    if len(args) != int(command == "hop"):
                        raise GardenError(node, f"Check the arguments for {command}().")
                    words = [command]
                else:
                    words = ["call", command]
                emit(" ".join(words + [direction(arg) for arg in args]), node.lineno)
            elif isinstance(node, ast.FunctionDef):
                args = node.args
                if (node.decorator_list or node.returns or getattr(node, "type_params", []) or
                    args.posonlyargs or args.vararg or args.kwonlyargs or args.kwarg or args.defaults or
                    any(arg.annotation for arg in args.args)):
                    raise GardenError(node, "Use a simple def with optional direction parameters.")
                routine = name(node.name, node)
                if routine in RESERVED_NAMES:
                    raise GardenError(node, "Choose a different name for this garden function.")
                routines.add(routine)
                emit(" ".join(["routine", routine, *(name(arg.arg, arg) for arg in args.args)]), node.lineno)
                block(node.body)
                emit("end", node.end_lineno)
            elif isinstance(node, (ast.If, ast.While)):
                keyword = "if" if isinstance(node, ast.If) else "while"
                if keyword == "while" and node.orelse:
                    raise GardenError(node, "Use else with if in the garden.")
                test = " or ".join(" and ".join(group) for group in clauses(node.test, routines))
                emit(f"{keyword} {test}", node.lineno)
                block(node.body)
                if node.orelse:
                    emit("else", node.orelse[0].lineno)
                    block(node.orelse)
                emit("end", node.end_lineno)
            elif isinstance(node, ast.For):
                iterator, args = arguments(node.iter)
                if (not isinstance(node.target, ast.Name) or node.target.id != "_" or node.orelse or
                    iterator != "range" or len(args) != 1 or not isinstance(args[0], ast.Constant) or
                    type(args[0].value) is not int or not 1 <= args[0].value <= 16):
                    raise GardenError(node, "Use for _ in range(N) with a count from 1 to 16.")
                emit(f"repeat {args[0].value}", node.lineno)
                block(node.body)
                emit("end", node.end_lineno)
            elif isinstance(node, (ast.Break, ast.Continue)):
                emit(type(node).__name__.lower(), node.lineno)
            else:
                raise GardenError(node, "Use garden calls, def, if, while, for, break, or continue.")

    if len(source) > MAX_SOURCE:
        return {"error": "Programs can contain up to 8,192 characters.", "line": 0}
    try:
        block(ast.parse(source, feature_version=(3, 10)).body)
    except SyntaxError as error:
        return {"error": error.msg, "line": max(0, (error.lineno or 1) - 1)}
    except GardenError as error:
        return {"error": str(error), "line": error.line}
    except RecursionError:
        return {"error": "Split this program into smaller expressions.", "line": 0}
    result = {"source": "\n".join(lines), "lines": locations}
    if diagnostics:
        result["diagnostics"] = diagnostics
    return result


if __name__ == "__main__":
    if sys.version_info < (3, 10):
        print(json.dumps({"error": "Lily Code Garden requires Python 3.10 or newer.", "line": 0}))
    else:
        print(json.dumps(lower(Path(sys.argv[1]).read_text(encoding="utf-8"))))
