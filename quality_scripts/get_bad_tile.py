#!/usr/bin/env python
import os
import numpy as np
import argparse
from astropy.io import fits

parser = argparse.ArgumentParser()
parser.add_argument("-o", "--obsid", type=str, required=True)
args = parser.parse_args()

obsid_str = args.obsid

meta_hdus = fits.open("metafits/%s.metafits" % obsid_str)

print(meta_hdus[1].data['Flag'])

#flags = meta_hdus[1].data['Flag']

#print(" ")

#print(np.count_nonzero(flags == 1))

#return(np.count_nonzero(flags == 1))
