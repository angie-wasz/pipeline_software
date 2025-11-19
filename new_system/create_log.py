import sys
import sqlite3 as lite
import argparse

def main(args):

	FILE = args['log']
	
	con = lite.connect(FILE)
	with con:
		cur = con.cursor()
		cur.execute("CREATE TABLE \
			Log(Rownum integer primary key autoincrement, \
			OBSID INT, \
			ASVOID INT, \
			Stage TEXT, \
			Status TEXT, \
			Time TEXT, \
			frac_bad REAL, \
			resid REAL)")


if __name__ == "__main__":
	
	parser = argparse.ArgumentParser()
	parser.add_argument("-l", "--log", type=str, required=True)
	args = parser.parse_args()

	main(vars(args))
	sys.exit(0)
