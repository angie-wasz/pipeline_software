# Produces the sun model for self-calibration, assuming the sun is a point source at the location of the sun (according to sunpy)
import argparse
import numpy as np
import astropy.units as u
from astropy.coordinates import get_sun
from astropy.time import Time

def main(args):
	
	data = args['data']
	obsid = args['obsid']
	freq = args['freq']

	f = (int(freq.split('-')[0])+0.5)*1.28

	t = Time(obsid, format='gps', scale='utc')
	sun = get_sun(t)
	
	sun_ra = sun.ra.to_string(u.hour, precision=1)
	sun_dec = sun.dec.to_string(u.degree, alwayssign=True, precision=0, pad=True)

	# Erickson model 
	erickson = 10**(-0.2+2.25*np.log10(f))

	# SUN MODEL FILE
	f_model = open(f"{data}/sun_model_{obsid}_{freq}.yaml", 'w+')
	f_model.write(f"super_sweet_source1:\n- ra: {sun.ra.deg:.1f}\n  dec: {sun.dec.deg:.1f}\n  comp_type: point\n  flux_type:\n    list:\n    - freq: {f*1e6:.1f}\n      i: {erickson:.1f}")
	f_model.close()

	# APPENDING YAML FILE
	f_yaml = open('pipeline-info.yaml', 'a+')
	f_yaml.write(f"  '{obsid}':\n")
	f_yaml.write(f"    ra: {sun_ra}\n")
	f_yaml.write(f"    dec: {sun_dec}\n")
	f_yaml.close()

if __name__ == '__main__':
	
	parser = argparse.ArgumentParser()
	parser.add_argument("-d", "--data", type=str, required=True, help='Data directory')
	parser.add_argument("-o", "--obsid", type=int, required=True, help='Obsid')
	parser.add_argument("-f", "--freq", type=str, default='114-115', help='Frequency channel that is being calibratred')
	args = parser.parse_args()

	main(vars(args))
