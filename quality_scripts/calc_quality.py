#!/usr/bin/env python3

import numpy as np
import math
#from astropy.time import Time
from datetime import datetime, timedelta
from astropy.io import fits
from aocal import fromfile
import argparse
import sys, os

MIN_POINTS = 3

def semihex(data, axis=None):
    """
    Calculate standard deviation via semi-interhexile range.
    """
    h1, h5 = np.nanpercentile(data, (100/6., 500/6.), axis=axis)
    return (h5-h1)/2

def fit_complex_gains(v, mode='model', amp_order=5, fft_pad_factor=8):
    """
    Fit amplitude & phases of a 1D array of complex values (v).
    Returns 1D array of complex values corresponding to the model
    NaN is treated as a flag. These values are excluded from the fit and
    persist in the returned model.
    Weight of each phase is taken to be abs(v)**-2 as is appropriate for
    interferometer calibration solutions (assuming low gain is indicative of
    poor sensitivity)
    A Coarse solution for the phases is determined via a padded FFT and average
    offset. This is then refined with a two-parameter least squares
    Amplitudes are fit using a polynomial, unless amp_order is set to <1, in
    which case amplitudes are preserved.
    """
    good = ~np.isnan(v) # mask matching non-NaN values
    if sum(good) == 0:
        return v
    v_fft = np.fft.fft(np.nan_to_num(v*np.abs(v)**-3), n=fft_pad_factor*len(v))
    v_index = np.arange(len(v), dtype=float)
    gradient = float(np.abs(v_fft).argmax())/len(v_fft) # change in phase per increment of v due to phase wrap
    wrap = np.array(np.cos(2*np.pi*v_index*gradient), dtype = np.complex128)
    wrap.imag = np.sin(2*np.pi*v_index*gradient)

    # unwrap v, keeping only valid values
    u = v[good]/wrap[good]
    u_index = np.arange(len(v), dtype=float)[good]
    # centre on 0
    u_mean = np.average(u)
    u_mean /= np.abs(u_mean)
    u0 = u/u_mean
    if np.var(np.angle(u0)) > 1:
        print("high variance detected in phases, check output model!")
    #print(np.angle(u0, deg=True))
    # finally do least squares
    m, c = np.polyfit(u_index, np.angle(u0), 1, w=np.abs(u)**-2)
    fit_complex = np.array(np.cos(v_index*m + c), dtype = np.complex128)
    fit_complex.imag = np.sin(v_index*m + c)
    # fit poly to amplitudes
    if amp_order > 0:
        amp_model_coeffs = np.polyfit(v_index[good], np.abs(v[good]), amp_order)
        amp_model = np.poly1d(amp_model_coeffs)(v_index)
    else:
        amp_model = np.abs(v)
    if mode=="model":
        return np.where(good, amp_model*fit_complex*wrap*u_mean, np.nan)
    elif mode=="clip":
        # check np.angle(u0) statistics
        # set "good" array to False where statistics are bad
        # return original array where not newly flagged
        #return np.where(good, v, np.nan)
        raise(RuntimeError, "clip not implemented")
    else:
        raise(RuntimeError, "mode %s not implemented" % mode)

def nanaverage(a, axis=None, weights=None):
    """
    weighted average treating NaN as zero
    """
    if weights is None:
        weights = np.ones(a.shape)
    return np.nansum(a*weights, axis=axis)/np.nansum(weights, axis=axis)

def get_tile_flavors(metafits):
    """
    return tile flavours ordered in AO order
    """
    hdus = fits.open(metafits)
    # This mirrors what cotter does (see metafitsfile.cpp MetaFitsFile::ReadTiles
    inputs = hdus[1].data
    tiles = inputs[inputs['pol'] == 'X']
    sort_ant = tiles['antenna'].argsort()
    return tiles['Flavors'][sort_ant]

def get_residuals(ao, skip=1, pols=(0, 3), int_times=(0,)):
    """
    compute residuals (in degrees) between model and actual phases
    """
    residual = np.nan*np.ones((len(int_times), ao.shape[1]//skip, len(pols), ao.shape[2]))
    pts = np.nan*np.ones((len(int_times), ao.shape[1]//skip, len(pols)))
    for i, interval in enumerate(int_times):
        for a, antenna in enumerate(range(0, ao.shape[1], skip)):
            for p, pol in enumerate(pols):
                v = ao[interval, antenna, :, pol]
                #print("indices %d %d %d" % (i, a, p), end=' ')
                num_pts = sum(~np.isnan(v))
                if num_pts > MIN_POINTS:
                    pts[i, a, p] = num_pts
                    model = fit_complex_gains(v)
                    residual[i, a, p] = np.angle((v/np.abs(v))/(model/np.abs(model)), deg=True)
                    #print("%02d: %05.1f" % (a, semihex(residual[i, a, p])))
                    #print("%02d: %05.1f %s" % (a, semihex(residual[i, a, p]), str(residual[i, a, p])))
    n = np.nanmedian(pts) # use to return a population variance-like quantity 
                          # (rather than sample variance-like quantity)
    return semihex(residual)*n/(n-2)

def get_flavor_divided(ao, metafits, refant="RG6_90"):
    ao_amp = np.abs(ao)
    flavors = get_tile_flavors(metafits).reshape(1, -1)
    if not refant in flavors:
        raise(RuntimeError, "refant flavor not found")
    # ao[flavors == refant] has shape (n_refant, n_freq, n_pol)
    ant_avg = nanaverage(ao[flavors == refant], axis=0, weights=ao_amp[flavors == refant]**-2) # correct phase
    ao = ao / ant_avg[np.newaxis, np.newaxis, :, :]
    return ao

def do_quality_calc(path, obs):
    #print(obs)
    t = float(obs)
    #obsids.append(t)
    #timestr = Time(t, format='gps').utc.isot
    obstime = datetime(1980, 1, 6) + timedelta(seconds=(t - (37-19)))
    timestr = datetime.strftime(obstime, "%Y-%m-%d %H:%M")
    #print(timestr[-1], end=' ')
    #f = f"{path}{obs}/{obs}_160.bin"
    f = f"{path}/{obs}_160.bin"
    ao = fromfile(f)
    frac_bad = float(np.sum(np.isnan(ao))+np.sum(ao == 0.0)) / np.prod(ao.shape)
    ao2 = get_flavor_divided(ao, f"{path}/{obs}.metafits")
    resid = get_residuals(ao2)
    #print("%d %4.2f %4.2f" % (obsids[-1], frac_bad[-1], resid[-1]))
    return timestr, frac_bad, resid


def main(args):

    log = args['log']
    obsid = args['obsid']
    path = args['path']

    timestr, frac_bad, resid = do_quality_calc(path, obsid)    

    if frac_bad is None:
        frac_bad = 1
    if math.isnan(resid):
        resid = 100

    print(frac_bad, resid)

    obs_dict = {'obsid':obsid, 'log':log, 'time':timestr, 'fracbad':frac_bad, 'resid':resid, \
				'asvo':None, 'initialise':False, 'status':None, 'stage':None, 'delete':False}
    update_log.main(obs_dict)


if __name__ == "__main__":
	
    parser = argparse.ArgumentParser("Get quality measurements for calibration solutions for a singular or list of observations (one or the other, not both)")
    parser.add_argument("-o", "--obsid", type=str, required=True)
    parser.add_argument("-p", "--path", type=str, required=True)
    parser.add_argument("-l", "--log", type=str, required=True)
    parser.add_argument("-s", "--software", type=str, required=True)
    args = parser.parse_args()
	
    script_dir = os.path.abspath(args.software)
    sys.path.insert(0, script_dir)
    import update_log

    main(vars(args))
