import argparse
from casacore.tables import table

parser = argparse.ArgumentParser()
parser.add_argument("--file", type=str, help="File name of measurement set")

args = parser.parse_args()

print(f"READING {args.file}")
tab = table(args.file, readonly=True)
print(tab.colnames())
