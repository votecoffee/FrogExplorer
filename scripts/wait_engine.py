"""Wait for the actual engine on Windows, including GUI-subsystem executables."""
import argparse
from pathlib import Path
import subprocess


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--log",type=Path,required=True)
    parser.add_argument("command",nargs=argparse.REMAINDER);args=parser.parse_args()
    command=args.command[1:] if args.command[:1]==["--"] else args.command
    if not command:parser.error("Supply the engine executable and arguments after --")
    args.log.parent.mkdir(parents=True,exist_ok=True)
    with args.log.open("wb") as output:
        process=subprocess.Popen(command,stdout=output,stderr=subprocess.STDOUT)
        try:code=process.wait()
        except KeyboardInterrupt:
            process.terminate()
            try:process.wait(timeout=5)
            except subprocess.TimeoutExpired:process.kill();process.wait()
            raise SystemExit(130)
    text=args.log.read_bytes().decode("utf-8",errors="replace")
    if code==0 and any(token in text for token in ["ERROR:","SCRIPT ERROR:","Parse Error"]):code=1
    raise SystemExit(code)


if __name__=="__main__":main()
