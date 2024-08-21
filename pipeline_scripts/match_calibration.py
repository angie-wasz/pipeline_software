#!/usr/bin/env python

from astropy.table import Table
from astropy.coordinates import SkyCoord
from astropy import units as u
from optparse import OptionParser

parser = OptionParser(usage = "usage: %prog input_cat reference output" +
"""

add various columns and delete unneeded ones.
""")

opts, args = parser.parse_args()



t1 = Table.read(args[0])
t2 = Table.read(args[1])

t1 = t1[~t1['ra'].mask]

ref = SkyCoord(t2['RAJ2000'], t2['DEJ2000'])
obs = SkyCoord(t1['ra']*u.deg, t1['dec']*u.deg)

idx, d2d, d3d = obs.match_to_catalog_sky(ref)

outcat = t1[d2d<2*u.arcmin] # t1 matches
outref = t2[idx[d2d<2*u.arcmin]] # t2 matches
outcat['Fp162'] = outref['Fp162']

outcat.write(args[2], format='votable')
