import os, math, csv

import numpy as np
import argparse
from datetime import datetime, timedelta

from astropy import units as u
from astropy.io import votable
from astropy.table import Table
from astropy.coordinates import SkyCoord
from sunpy.coordinates import Helioprojective
from sunpy.time import parse_time


def parse_args():
    
    parser = argparse.ArgumentParser()

    parser.add_argument('-f', "--file", type=str, required=True)
    parser.add_argument('-y', "--year", type=int, required=True)

    args = parser.parse_args()

    if len(str(args.year)) < 4:
        parser.error('Invalid YEAR')


    if not os.path.exists(args.file):
        parser.error('Invalid file')

    return args


def extract_info(obs, year):

    all_sources = []

    # Date related things
    obstime = datetime(1980, 1, 6) + timedelta(seconds=(float(obs) - (37-19)))
    date = datetime.strftime(obstime, "%Y-%m-%d %H:%M")

    # Open up _glevel.vot file
    DIR = "/media/angelica/mwasolar-backup/mwa-solar/ips/pipeline/"
    TAB = f"{DIR}/{str(year)}/{str(obs)}/{str(obs)}_121-132_glevel.vot"
    if not os.path.isfile(TAB):
        TAB = f"{DIR}/{str(year)}/{str(obs)}/{str(obs)}_glevel.vot"
        if not os.path.isfile(TAB):
            print(f"ERROR: g-level data time {TAB} does not exist")
            exit(1)    

    mwa = votable.parse_single_table(TAB).array

    sources = mwa['GLEAM_1']
    for i, source in enumerate(sources):

        # There is some filtering 
        # snr > 5
        # g > 0
        g = mwa['g'][i]
        if g > 0:
            snr_g = mwa['snr_scint'][i]
            if snr_g > 0:
                
                ra = mwa['RAJ2000_1'][i]
                dec = mwa['DEJ2000_2'][i]

                #Helioprojective transform
                radec = SkyCoord(ra*u.deg, dec*u.deg, distance=1e9*u.parsec)
                helio = radec.transform_to(Helioprojective(obstime=obstime, observer='Earth'))
                tx = helio.Tx.deg
                ty = helio.Ty.deg

                elon = mwa['elongation2'][i]
                limb = mwa['limb'][i]
                sun_lat = mwa['sun_lat'][i]
                flux = mwa['peak_flux'][i]
                rms = mwa['local_rms'][i]
                snr = mwa['snr'][i]
                nsi = mwa['nsi_fit'][i]
                nsi_err = mwa['nsi_err'][i]
                ds = mwa['dS2'][i]
                rms2 = mwa['local_rms2'][i]
                snr_scint = mwa['snr_scint'][i]
                m1 = mwa['mpt1'][i]
                m2 = mwa['mpt2'][i]
                g_err = mwa['g_err'][i]

                all_sources.append((obs, date, source, ra, dec, tx, ty, elon, limb, sun_lat, flux, rms, snr, nsi, nsi_err, ds, rms2, snr_scint, m1, m2, g, snr_g, g_err))
    
    return all_sources


def main():

    args = parse_args()
    year = args.year
    in_list = args.file

    obsids = []
    with open(in_list, 'r+') as file:
        for line in file:
            obsids.append(line.strip())
    obsids = np.array(obsids)

    # Create table
    N = len(obsids)*500
    
	# Define the columns
    dtype = [
        ('obsid', 'int'),
        ('UTC_datetime', 'U16'),
        ('GLEAM', 'U24'),
        ('RAJ2000', 'float'),
        ('DEJ2000', 'float'),
        ('Tx', 'float'),
        ('Ty', 'float'),
        ('elongation', 'float'),
        ('limb', 'U1'),
        ('sun_lat', 'float'),
        ('peak_flux', 'float'),
        ('local_rms', 'float'),
        ('snr', 'float'),
        ('nsi_fit', 'float'),
        ('nsi_err', 'float'),
        ('dS2', 'float'),
        ('local_rms2', 'float'),
        ('snr_scint', 'float'),
        ('mpt1', 'float'),
        ('mpt2', 'float'),
        ('g', 'float'),
        ('snr_g', 'float'),
		('g_err', 'float')
	]
    table = Table(data=np.zeros(N, dtype=dtype))

    past_sources = 0
    for i in range(len(obsids)):
        print(f"Starting {obsids[i]}")
        data = extract_info(obsids[i], year)
        for j in range(len(data)):
            table[j+past_sources] = data[j]
        print(f"Finished: {obsids[i]}")
        past_sources += len(data)

    # File that will store the information
    out_file = f"{year}_scin_info.vot"

    # Save the table to the file
    table.write(out_file, format='votable', overwrite=True)

if __name__ == '__main__':
    main()
