#!/usr/bin/env python3

import sqlite3 as lite
import argparse
import sys

def main(args):

	FILE = args['log']
	obsid = args['obsid']

	con = lite.connect(FILE)
	with con:
		cur = con.cursor()
	
		if args['initialise']:
			cur.execute("INSERT INTO Log (OBSID, ASVOID, Stage, Status, Time, frac_bad, resid) VALUES (?, ?, ?, ?, ?, ?, ?)", \
				(obsid, 0, "INIT", "INIT", "None", 0, 0))

		if args['delete']:
			cur.execute("DELETE FROM Log WHERE OBSID=%d" % (obsid))

		else:
			if args['asvo'] is not None:
				cur.execute("UPDATE Log SET ASVOID=? WHERE OBSID=?", (args['asvo'], obsid))
			if args['stage'] is not None:
				cur.execute("UPDATE Log SET Stage=? WHERE OBSID=?", (args['stage'], obsid))
			if args['status'] is not None:
				cur.execute("UPDATE Log SET Status=? WHERE OBSID=?", (args['status'], obsid))
			if args['time'] is not None:
				cur.execute("UPDATE Log SET Time=? WHERE OBSID=?", (args['time'], obsid))		
			if args['fracbad'] is not None:
				cur.execute("UPDATE Log SET frac_bad=? WHERE OBSID=?", (args['fracbad'], obsid))		
			if args['resid'] is not None:
				cur.execute("UPDATE Log SET resid=? WHERE OBSID=?", (args['resid'], obsid))		


if __name__ == "__main__":

	if len(sys.argv) < 2:
		sys.exit(1)
	
	parser = argparse.ArgumentParser()
	parser.add_argument("-o", "--obsid", type=int, required=True)
	parser.add_argument("-l", "--log", type=str, required=True)
	parser.add_argument("--initialise", action="store_true")
	parser.add_argument("--delete", action="store_true")
	parser.add_argument("--asvo", type=int)
	parser.add_argument("--stage", type=str)
	parser.add_argument("--status", type=str)
	parser.add_argument("--time", type=str)
	parser.add_argument("--fracbad", type=float)
	parser.add_argument("--resid", type=float)
	args = parser.parse_args()

	main(vars(args))
	sys.exit(0)
