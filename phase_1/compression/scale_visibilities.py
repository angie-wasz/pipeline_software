import argparse
import numpy as np
from casacore.tables import table

#virA_scale = np.float32(23.24)

def scale(ms, virA_scale):

	with table(ms, readonly=False) as tab:
		data = tab.getcol("CORRECTED_DATA")
		data = data * virA_scale
		tab.putcol("CORRECTED_DATA", data)

if __name__ == "__main__":

	parser = argparse.ArgumentParser()
	parser.add_argument("--file", type=str, help="File name of measurement set")
	parser.add_argument("--scale", type=float, help="Scaling factor found from VirgoA")

	args = parser.parse_args()

	scale(args.file, args.scale)
