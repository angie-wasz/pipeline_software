#!/usr/bin/env python3

import sqlite3 as lite
import argparse

def main():
	parser = argparse.ArgumentParser()
	parser.add_argument("-o", "--obsid", type=int)
	parser.add_argument("-l", "--log", type=str, required=True)
	parser.add_argument("--quality", action='store_true')
	parser.add_argument("--imaged", action='store_true')
	args = parser.parse_args()

	FILE = args.log

	query = "SELECT * FROM Log"

	if args.imaged:
		query += ''' WHERE Stage="Imaging" OR Stage="Post-Image"'''
	
	if args.obsid is not None:
		query += ''' WHERE OBSID=%d''' % (args.obsid)
	else:
		query += ''' ORDER BY OBSID ASC'''


	con = lite.connect(FILE)
	with con:
		cur = con.cursor()
		cur.execute(query)
		rows = cur.fetchall()

	for row in rows:

		obsid = row[1]
		asvoid = row[2]
		stage = row[3]
		status = row[4]

		if args.quality:
			if asvoid != 0:
				print(f"OBSID: {row[1]} | frac_bad: {row[6]:.2f} | resid: {row[7]:.1f}")
		else:
			print(f"OBSID: %d | ASVOID: %d | Stage: %s | Status: %s" % (obsid, asvoid, stage, status))
		

if __name__ == "__main__":
	main()
