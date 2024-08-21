#!/usr/bin/env python

import os, sys
import logging
import numpy as np
from h5py import File
from astropy.io import votable
from optparse import OptionParser #NB zeus does not have argparse!

IN_DIR="."

if __name__ == '__main__':
    parser = OptionParser(usage="usage: imstack freq")

    opts, args = parser.parse_args()
    if len(args) != 2:
        parser.error("incorrect number of arguments")

    imstack = args[0]
    freq = args[1]

    with File(imstack, 'r') as imstack:
        group = imstack[freq]
        beam = group['beam']
        print(args[0],end=' ')
        print('scale', np.squeeze(beam.attrs['SCALE']), end=' ')
        #print('scalen', beam.attrs['SCALEN'])
        #print('scalef', beam.attrs['SCALEF'])
        print('sigma', np.squeeze(beam.attrs['SIGMA']))
