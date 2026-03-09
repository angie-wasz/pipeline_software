#!/usr/bin/env python
from h5py import File
import sys
import numpy as np
from astropy.io import fits

from optparse import OptionParser

parser = OptionParser()
parser.add_option("--freq", dest="freq", default="121-132", help="frequency")
opts, args = parser.parse_args()
freq=opts.freq

POLS = ('XX', 'YY')
obsid=sys.argv[1]
noise = []
for pol in POLS:
    hdus = fits.open(f"{obsid}_{freq}image_moment2-{pol}.fits")
    noise.append(np.median(hdus[0].data))

hdf5_file=f"{obsid}_{freq}.hdf5"
with File(hdf5_file, 'r+') as imstack:
    group = imstack[freq]
    beam = group['beam']
    beam.attrs['SIGMA'] = np.array(noise)
    print(beam.attrs['SIGMA'])
