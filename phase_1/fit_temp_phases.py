# Rewrite to only take a single observation and to work on Setonix

import argparse, os
import numpy as np
import pandas as pd

from astropy.io import fits
from astropy.time import Time
from astropy.table import Table

from iminuit import Minuit
from iminuit.cost import LeastSquares
from functools import partial

import matplotlib.pyplot as plt
from matplotlib.gridspec import GridSpecFromSubplotSpec

REFANT = 2
ERROR=0.1
NUM_FREQ_CHANNELS=10
FLAVOR_LENGTHS = np.array([90, 150, 230, 320, 400, 524])

def parse_args():
    
    parser = argparse.ArgumentParser()

    parser.add_argument('-o', '--obsid', type=str, required=True, help='Obsid')
    parser.add_argument('-d', '--data', type=str, required=True, help='Path to the data directory containing the metafits and calibration solutions')
    parser.add_argument('-f', '--freq', type=str, default='129-130', help='The frequency channels of the observation')
    parser.add_argument('--fine_chans', type=int, default=64, help='The number of fine channels')
    parser.add_argument('--cal_obs', type=int, required=True, help='Calibrator observation')
    parser.add_argument('--fit_gradient', type=float, help='Will overwrite the temperature ramp found from observations')

    args = parser.parse_args()

    return args


def get_temps(metafits_hdus):

    bftemps = metafits_hdus[1].data["BFTEMPS"][metafits_hdus[1].data["Pol"]=="X"]
    temp = np.median(bftemps)
    sun_alt = metafits_hdus[0].header["SUN-ALT"]

    return temp


def plot_phase_diffs(obs, cal_obs, freq, dist, diff_angle, rg6_90, rg6_150, rg6_230):

    fig, ax = plt.subplots(1, 1, figsize=(8,8), dpi=120)

    ax.scatter([np.min(dist)], [0], marker='*', s=200, label="Reference antenna", color='tab:pink')

    ax.plot(dist[rg6_90], diff_angle[rg6_90][:, 0], 'o', label='RG6_90 X', color='rebeccapurple')
    ax.plot(dist[rg6_150], diff_angle[rg6_150][:, 0],'o', label='RG6_150 X', color='tab:green')
    ax.plot(dist[rg6_230], diff_angle[rg6_230][:, 0],'o', label='RG6_230 X', color='orange')

    ax.plot(dist[rg6_90], diff_angle[rg6_90][:, 1], '+', label='RG6_90 Y', color='rebeccapurple')
    ax.plot(dist[rg6_150], diff_angle[rg6_150][:, 1],'+', label='RG6_150 Y', color='tab:green')
    ax.plot(dist[rg6_230], diff_angle[rg6_230][:, 1],'+', label='RG6_230 Y', color='orange')

    ax.axvline(np.min(dist), lw=1, ls=':', c='tab:pink')
    ax.axhline(0, lw=1, ls=':', c='tab:pink')

    ax.set_title(f"Solar: {obs}  Cal: {cal_obs}  Freq: {freq}")

    ax.set_ylim(-np.pi, np.pi)
    ax.legend()

    fig.savefig(f"{data}/{obs}_{freq}_phase_diffs.png", bbox_inches='tight')

    plt.close()


def main():
	
    obsid = args['obsid']
    obsid_cal = args['cal_obs']
    data = args['data']
    freq = args['freq']
    fine_chans = args['fine_chans']


    # DATAFRAME
    # Save the fit parameters for each observation and frequency
    fit_params = pd.DataFrame(columns=['obs_solar', 'obs_cal', 'freq_ch', 'temp_diff', 'north_ramp', 'east_ramp', 'rg6_90_delay', 'rg6_90_err', 'rg6_150_delay', 'rg6_150_err', 'rg6_230_delay', 'rg6_230_err', 'fit_gradient', 'fit_err'])
    

    # METAFITS
    metafits_solar = fits.open(f"{data}/{obsid}.metafits")
    metadata_solar = metafits_solar[1].data[metafits_solar[1].data["Pol"]=="X"]

    metafits_cal = fits.open(f"{data}/{obsid_cal}.metafits")
    metadata_cal = metafits_cal[1].data[metafits_cal[1].data["Pol"]=="X"]


    # TEMPERATURE
    solar_temp = get_temps(metafits_solar)
    cal_temp = get_temps(metafits_cal)
    temp_diff = solar_temp - cal_temp


    # TILE FLAVOURS
    names = metadata_cal["Tile"]
    assert np.all(names==metadata_solar["Tile"]), "Flavors do not match!"
    order = np.argsort(names)
    names = names[order]

    flavors = metadata_cal["Flavors"]
    assert np.all(flavors==metadata_solar["Flavors"]), "Flavors do not match!"
    flavors = flavors[order]

    coords = np.array((metadata_cal["North"], metadata_cal["East"])).T
    assert np.all(coords == np.array((metadata_solar["North"], metadata_solar["East"])).T)
    coords = coords[order]

    coords -= coords[REFANT]
    dist = np.hypot(coords[:, 0], coords[:, 1])

    FLAVOR_NAMES = sorted(set(flavors), key=lambda x: int(x.split('_')[1]))
    FLAVOR_LENGTHS = sorted([float(x.split('_')[1]) for x in FLAVOR_NAMES])
    REF_FLAVOR_LENGTH=FLAVOR_LENGTHS[FLAVOR_NAMES.index(flavors[REFANT])]


    # CALIBRATION SOLUTIONS
    # Self-cal
    TAB = f"{data}/{obsid}_ch{freq}_sols_160.fits"
    if not os.path.exists(TAB):
        print(f"{obsid} Self-cal solutions don't exist")
        exit()
    sol_solar = fits.open(TAB)
    raw_solar = sol_solar[1].data.squeeze()

    # Calibrator
    TAB = f"{data}/{obsid_cal}_ch{freq}_sols_160.fits"
    if not os.path.exists(TAB):
        print(f"{obsid_cal} Calibrator solutions don't exist")
        exit()
    sol_cal = fits.open(TAB)
    raw_cal = sol_cal[1].data.squeeze()


    # NO REFERENCE TILE
    noref_solar = np.zeros((128, raw_solar.shape[1], 2), dtype=complex)
    noref_cal = np.zeros((128, raw_cal.shape[1], 2), dtype=complex)

    noref_solar[..., 0].real = raw_solar[..., 0]
    noref_solar[..., 0].imag = raw_solar[..., 1]
    noref_solar[..., 1].real = raw_solar[..., 6]
    noref_solar[..., 1].imag = raw_solar[..., 7]

    noref_cal[..., 0].real = raw_cal[..., 0]
    noref_cal[..., 0].imag = raw_cal[..., 1]
    noref_cal[..., 1].real = raw_cal[..., 6]
    noref_cal[..., 1].imag = raw_cal[..., 7]


    # BY FLAVOUR
    flag_by_antenna = np.sum(np.isfinite(noref_solar[..., 1]), axis=1)
    rg6_90 = (flavors=="RG6_90")&(flag_by_antenna>NUM_FREQ_CHANNELS)
    rg6_150 = (flavors=="RG6_150")&(flag_by_antenna>NUM_FREQ_CHANNELS)
    rg6_230 = (flavors=="RG6_230")&(flag_by_antenna>NUM_FREQ_CHANNELS)


    # COMPARE
    ref_cal = noref_cal[REFANT]/np.abs(noref_cal[REFANT][None, ...])
    cal = noref_cal/ref_cal

    ref_solar = noref_solar[REFANT]/np.abs(noref_solar[REFANT][None, ...])
    solar = noref_solar/ref_solar

    caldiff = solar / cal
    diff_angle = np.nanmedian(np.angle(caldiff), axis=1)
    diff_angle_fine = np.angle(caldiff)

	print(f"{obsid} Plotting phase differences")
    plot_phase_diffs(obsid, obsid_cal, freq, dist, diff_angle, rg6_90, rg6_150, rg6_230)


    # FIT PHASES
    def offset_and_flavor(north_ramp, east_ramp, rg6_90_delay, rg6_150_delay, rg6_230_delay):
        '''
        NB coords, rg6_90, rg6_150 and rg6_23 are used directly, not passed in
        '''
        phases = coords[:, 0]*north_ramp + coords[:, 1]*east_ramp
        phases[rg6_90] += rg6_90_delay
        phases[rg6_150] += rg6_150_delay
        phases[rg6_230] += rg6_230_delay
        return phases

    model_phases = np.zeros([cal.shape[0], cal.shape[1]])
    freqs = np.linspace(int(freq.split('-')[0]), int(freq.split('-')[1])+1, fine_chans)*1.28

    fit_gradients = []
	print(f"{obsid} Fitting temperature ramp per fine channel")
    for chan in range(fine_chans):

        def least_squares(north_ramp, east_ramp, rg6_90_delay, rg6_150_delay, rg6_230_delay):
            return np.nansum((diff_angle_fine[:, chan]-offset_and_flavor(north_ramp, east_ramp, rg6_90_delay, rg6_150_delay, rg6_230_delay)[:, None])**2)/ERROR**2

        m = Minuit(least_squares, north_ramp=0, east_ramp=0,
        rg6_90_delay=0,
        rg6_150_delay=np.nanmedian(diff_angle_fine[rg6_150, chan, :]),
        rg6_230_delay=np.nanmedian(diff_angle_fine[rg6_230, chan, :]))
        m.migrad()

        linear = lambda x, m, c: m*x + c
        least_squares_cable = LeastSquares([90-REF_FLAVOR_LENGTH, 150-REF_FLAVOR_LENGTH, 230-REF_FLAVOR_LENGTH], 
                                    [m.values['rg6_90_delay'], m.values['rg6_150_delay'], m.values['rg6_230_delay']],
                                    [m.errors['rg6_90_delay'], m.errors['rg6_150_delay'], m.errors['rg6_230_delay']],
                                    linear)

        if args['fit_gradient'] is not None:
            fit_gradient_dict = {'m':args['fit_gradient'], 'c':0}
        else:
            m_cable_delay = Minuit(least_squares_cable, m=0, c=0)
            m_cable_delay.migrad()
            fit_gradient_dict = m_cable_delay.values.to_dict()
            fit_gradients.append([freqs[chan], m_cable_delay.values['m'], m_cable_delay.errors['m']])

        for i in range(3):
            mask = (flavors==FLAVOR_NAMES[i])
            model_phases[mask, chan] = linear(FLAVOR_LENGTHS[i]-150, **fit_gradient_dict)
            mask = (flavors==FLAVOR_NAMES[i+3])
            model_phases[mask, chan] = linear(FLAVOR_LENGTHS[i+3]-150, **fit_gradient_dict)*1.4


    # TEMP ADJUST CALIBRATION SOLUTIONS
    solar_adjusted = np.zeros((1, raw_cal.shape[0], raw_cal.shape[1], 4), dtype=complex)
    cal_copy = sol_cal.copy()
    
    c = np.cos(model_phases)
    d = np.sin(model_phases)

    for i in range(4):

        a = sol_cal[1].data[0, :, :, i*2]
        b = sol_cal[1].data[0, :, :, i*2+1]

        solar_adjusted[0, :, :, i].real = a*c - b*d
        solar_adjusted[0, :, :, i].imag = a*d + b*c

        cal_copy[1].data[0, :, :, i*2] = solar_adjusted[0, :, :, i].real
        cal_copy[1].data[0, :, :, i*2+1] = solar_adjusted[0, :, :, i].imag

    cal_copy.writeto(f"{data}/cal_sol_ch{freq}_sols_fine_160.fits", overwrite=True)


    # SAVE FIT PARAMS
    m_grad_avg = np.mean(fit_gradients, axis=0)[1]
    m_err_avg = np.mean(fit_gradients, axis=0)[2]
    fit_params.loc[i] = [obsid, obsid_cal, freq, temp_diff, m.values['north_ramp'], m.values['east_ramp'], m.values['rg6_90_delay'], m.errors['rg6_90_delay'], m.values['rg6_150_delay'], m.errors['rg6_150_delay'], m.values['rg6_230_delay'], m.errors['rg6_230_delay'], m_grad_avg, m_err_avg]
    fit_params.to_csv(f'{data}/{obsid}_{freq}_fit_params.csv', index=False)
    np.savetxt(f'{data}/{obsid}_{freq}_finechan_fits.txt', np.array(fit_gradients), delimiter=',')


if __name__ == "__main__":

    args = parse_args()

    main(vars(args))
