#!/usr/bin/env python
import os
import numpy as np
from astropy.table import Table
from astropy.time import Time
from astropy.units import deg
from astropy.coordinates import SkyCoord, get_sun
from image_stack import ImageStack
from scipy.optimize import minimize


from optparse import OptionParser, OptionValueError

POL_OPTIONS=("XX", "YY", "I")

parser = OptionParser(usage = "usage: %prog input.hdf5 input.vot output.vot" +
"""

add various columns and delete unneeded ones.
""")
parser.add_option("-v", "--variability", dest="var", action="store_true", help="Calculate variability image parameters (dS etc)")
parser.add_option("-o", "--obsid", dest="obsid", default=None, help="time in gps format used for calculation of Sun location (default: first 10 letters of input.hdf5)")
parser.add_option("--pol", dest="pol", default="I", help="primary beam polarisation to use: {} (default=%default)".format((", ".join(POL_OPTIONS))))

opts, args = parser.parse_args()
#FIXME add options for 
# freq
# ra column name
# dec column name
# new column name
# out table format
# variability
# gpstime
# set verbosity

if opts.var and opts.interp:
    raise OptionValueError("-v/--variability can not be set with -i/--interp")
if not opts.pol in POL_OPTIONS:
    raise OptionValueError("polarisation must be one of %s" % (", ".join(POL_OPTIONS)))
if os.path.exists(args[2]):
    os.remove(args[2])
imstack = ImageStack(args[0], freq='121-132')
dim_x, dim_y = imstack.group['beam'].shape[1:3]

t = Table.read(args[1])

# elongation
if not opts.obsid:
    opts.obsid = args[0][:10]
print("calculating elongations")
time = Time(float(opts.obsid), format='gps')
sun = get_sun(time.utc)
#t['elongation'] = sun.separation(SkyCoord(t['ra', 'dec']*deg))
t['elongation'] = sun.separation(SkyCoord(t['ra'], t['dec'], unit = "deg"))
t['snr'] = t['peak_flux'] / t['local_rms']

print("calculating primary beam")
t["pbcor"] = np.nan*np.ones(len(t))
# loop over all unmasked values
for s in np.argwhere(~t['ra'].mask)[:, 0]:
    #print(s, sep=' ')
    x, y = imstack.world2pix(t['ra'][s], t['dec'][s])
    #print(x,y)
    if x<0 or x >= dim_x:
        continue
    if y<0 or y >= dim_y:
        continue
    if opts.pol == "I":
        t["pbcor"][s] = imstack.pix2beam(x, y, scale=True)
    elif opts.pol == "XX":
        t["pbcor"][s] = np.squeeze(imstack.pix2beam(x, y, avg_pol=False, scale=True))[0]
    elif opts.pol == "YY":
        t["pbcor"][s] = np.squeeze(imstack.pix2beam(x, y, avg_pol=False, scale=True))[1]

f = lambda x: -imstack.pix2beam(int(x[0]), int(x[1]), scale=True)
min_ = minimize(f, (1200, 1200), method='Nelder-Mead', options={'xatol': 1})
pbmax = -min_['fun']
t["pbcor_norm"] = t["pbcor"]/pbmax

if opts.var:
    t['dS'] = np.sqrt((t['peak_flux']+t['background'])**2 - t['background']**2)
    t['err_dS'] = np.sqrt((t['peak_flux']+t['background']+t['local_rms'])**2 - t['background']**2) - t['dS']
    t.keep_columns(['ra', 'err_ra', 'dec', 'err_dec', 'a', 'b', 'pa', 'elongation', 'pbcor', 'pbcor_norm', 'uuid', 'dS', 'err_dS', 'background', 'local_rms', 'snr'])
else:
    t.keep_columns(['ra', 'err_ra', 'dec', 'err_dec', 'a', 'b', 'pa', 'elongation', 'pbcor', 'pbcor_norm', 'uuid', 'peak_flux', 'background', 'local_rms', 'snr'])

print("writing votable")
t.write(args[2], format='votable')
