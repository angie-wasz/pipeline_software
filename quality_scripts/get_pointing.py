#!/usr/bin/env python
import sys
from argparse import ArgumentParser
from astropy.io import fits
from astropy import units as u

parser = ArgumentParser()
parser.add_argument("directory", default=None, help="Path to directory where metafits and output to be saved")
parser.add_argument("obsid", default=None, help="Observation ID", type=str)
args = parser.parse_args()

directory = args.directory
obsid = args.obsid

hdu = fits.open(f"{directory}/{obsid}.metafits")
#print(f"{hdu[0].header['RA']:.2f}")
#print(f"{hdu[0].header['DEC']:.2f}")

with open(f"{directory}/{obsid}_point.txt", "w") as f:
    f.write(f"RA {hdu[0].header['RA']:.2f}\n")
    f.write(f"DEC {hdu[0].header['DEC']:.2f}\n")

