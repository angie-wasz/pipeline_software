# Rewrite to only take a single observation

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

def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument('-o', '--obsid', type=str, required=True, help='Obsid')
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

    fig.savefig(f"cal/sun_as_point_source/{obs}/{obs}_compare_phases.png", bbox_inches='tight')

    plt.close()


def plot_phase_fits(obs, cal_obs, freq, m, REF_FLAVOR_LENGTH, linear, m_cable_delay):
        
    fig = plt.figure(figsize=(16,5), dpi=120)

    gs_outer = plt.GridSpec(1, 2, width_ratios=[1, 2], wspace=0.15)
    ax1 = fig.add_subplot(gs_outer[0])
    ax1.set_xlim([-0.25, 0.25])
    ax1.set_ylim([-0.25, 0.25])
    ax1.set_xlabel("Projected East offset [deg]")
    ax1.set_ylabel("Projected North offset [deg]")
    ax1.axvline(0, ls=':', lw=1, color='grey')
    ax1.axhline(0, ls=':', lw=1, color='grey')
    ax1.set_aspect("equal")

    gs_right = GridSpecFromSubplotSpec(1, 2, subplot_spec=gs_outer[1], wspace=0.05)
    ax2 = fig.add_subplot(gs_right[0])
    ax2.set_ylim([-2.0, 0.2])
    ax2.set_xlabel("Relative cable length [m]")
    ax2.set_ylabel("Cable phase delay [rad]")

    ax3 = fig.add_subplot(gs_right[1], sharey=ax2)
    ax3.tick_params(labelleft=False)
    ax3.set_xlabel("Relative cable length [m]")

    a = np.degrees(0.5)

    ax1.errorbar([a*m.values['east_ramp']],
                [a*m.values['north_ramp']],
                xerr=[a*m.errors['east_ramp']],
                yerr=[a*m.errors['north_ramp']],
                fmt='o',
                color='rebeccapurple')

    ax2.errorbar([90-REF_FLAVOR_LENGTH, 150-REF_FLAVOR_LENGTH, 230-REF_FLAVOR_LENGTH],
                [m.values['rg6_90_delay'], m.values['rg6_150_delay'], m.values['rg6_230_delay']],
                yerr=[m.errors['rg6_90_delay'], m.errors['rg6_150_delay'], m.errors['rg6_230_delay']],
                fmt='o:')
    ax2.plot(FLAVOR_LENGTHS[:3]-150, linear(FLAVOR_LENGTHS[:3]-150, **m_cable_delay.values.to_dict()), '--', lw=1, markersize=10)

    ax3.errorbar([90-150, 150-150, 230-150],
                [m.values['rg6_90_delay'], m.values['rg6_150_delay'], m.values['rg6_230_delay']],
                yerr=[m.errors['rg6_90_delay'], m.errors['rg6_150_delay'], m.errors['rg6_230_delay']],
                fmt='o', label='Data')
    ax3.plot(FLAVOR_LENGTHS-150, linear(FLAVOR_LENGTHS-150, **m_cable_delay.values.to_dict()), '+--', lw=1, markersize=10, label='RG6 Fit')
    ax3.plot(FLAVOR_LENGTHS-150, linear(FLAVOR_LENGTHS-150, **m_cable_delay.values.to_dict())*1.4, '+--', lw=1, markersize=10, label='LMR400 Fit')
    
    ax3.legend()

    ax2.set_title(f"Solar: {obs}  Cal: {cal_obs}  Freq: {freq}")

    fig.savefig(f"cal/sun_as_point_source/{obs}/{obs}_fit_phases.png", bbox_inches='tight')

    plt.close()


REFANT = 2
ERROR=0.1
NUM_FREQ_CHANNELS=10
FLAVOR_LENGTHS = np.array([90, 150, 230, 320, 400, 524])

def main():
	
	obsid = args['obsid']
	cal_obsid = args['cal_obsid']

    # tab = Table.read("phase1_2013.fits")
    tab = pd.read_csv("phase1_2013_calibrators.csv")
    solar_obsids = np.loadtxt(args.list, dtype=int)

    freq = args.freq
    fine_chans = args.fine_chans

    # fit_params = pd.DataFrame(columns=['obs_solar', 'obs_cal', 'freq_ch', 'temp_diff', 'north_ramp', 'east_ramp', 'rg6_90_delay', 'rg6_90_err', 'rg6_150_delay', 'rg6_150_err', 'rg6_230_delay', 'rg6_230_err', 'fit_gradient', 'fit_err'])
    # fit_gradients = []

    for i, obsid_solar in enumerate([solar_obsids]):

        first_obsid = 1063683616
        obsid_cal = int(tab['cal_obsid'][np.where((tab['first_obsid'] == first_obsid) & (tab['freq_ch'] == freq))[0][0]])

        # FOR GLEAM
        # obsid_cal = args.cal_obs

        if obsid_cal > 0:

            # METAFITS
            metafits_solar = fits.open(f"metafits/{obsid_solar}.meta.fits")
            metadata_solar = metafits_solar[1].data[metafits_solar[1].data["Pol"]=="X"]

            metafits_cal = fits.open(f"metafits/{obsid_cal}.meta.fits")
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
            # TAB = f"obsids/{obsid_solar}/{obsid_solar}_sols.fits"
            # FOR GLEAM
            TAB = f"obsids/{obsid_solar}/{obsid_solar}_ch{freq}_sols_160.fits"
            if not os.path.exists(TAB):
                print(f"{obsid_solar} Self-cal solutions don't exist")
                continue
            cal_solar = fits.open(TAB)
            cal_raw_solar = cal_solar[1].data.squeeze()

            TAB = f"calibrators/{obsid_cal}/{obsid_cal}_ch{freq}.fits"
            if not os.path.exists(TAB):
                TAB = f"calibrators/{obsid_cal}/{obsid_cal}_ch{freq}_sols_160.fits"
                if not os.path.exists(TAB):
                    print(f"{obsid_solar} Calibrator solutions don't exist")
                    continue
            cal_cal = fits.open(TAB)
            cal_raw_cal = cal_cal[1].data.squeeze()


            # NO REFERENCE TILE
            cal_noref_solar = np.zeros((128, cal_raw_solar.shape[1], 2), dtype=complex)
            cal_noref_cal = np.zeros((128, cal_raw_cal.shape[1], 2), dtype=complex)

            cal_noref_solar[..., 0].real = cal_raw_solar[..., 0]
            cal_noref_solar[..., 0].imag = cal_raw_solar[..., 1]
            cal_noref_solar[..., 1].real = cal_raw_solar[..., 6]
            cal_noref_solar[..., 1].imag = cal_raw_solar[..., 7]

            cal_noref_cal[..., 0].real = cal_raw_cal[..., 0]
            cal_noref_cal[..., 0].imag = cal_raw_cal[..., 1]
            cal_noref_cal[..., 1].real = cal_raw_cal[..., 6]
            cal_noref_cal[..., 1].imag = cal_raw_cal[..., 7]


            # BY FLAVOUR
            flag_by_antenna = np.sum(np.isfinite(cal_noref_solar[..., 1]), axis=1)
            rg6_90 = (flavors=="RG6_90")&(flag_by_antenna>NUM_FREQ_CHANNELS)
            rg6_150 = (flavors=="RG6_150")&(flag_by_antenna>NUM_FREQ_CHANNELS)
            rg6_230 = (flavors=="RG6_230")&(flag_by_antenna>NUM_FREQ_CHANNELS)


            # COMPARE
            ref_cal = cal_noref_cal[REFANT]/np.abs(cal_noref_cal[REFANT][None, ...])
            cal = cal_noref_cal/ref_cal
            ref_solar = cal_noref_solar[REFANT]/np.abs(cal_noref_solar[REFANT][None, ...])
            solar = cal_noref_solar/ref_solar
            caldiff = solar / cal
            diff_angle = np.nanmedian(np.angle(caldiff), axis=1)
            diff_angle_fine = np.angle(caldiff)

            # plot_phase_diffs(obsid_solar, obsid_cal, freq, dist, diff_angle, rg6_90, rg6_150, rg6_230)


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

            # The fit now is done for each fine channel
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

                # print(chan, m_cable_delay.values['m'], m_cable_delay.errors['m'])
                # fit_gradients.append([freqs[chan], m_cable_delay.values['m'], m_cable_delay.errors['m']])

                if args.fit_gradient is not None:
                    fit_gradient_dict = {'m':args.fit_gradient, 'c':0}
                else:
                    m_cable_delay = Minuit(least_squares_cable, m=0, c=0)
                    m_cable_delay.migrad()
                    fit_gradient_dict = m_cable_delay.values.to_dict()

                for i in range(3):
                    mask = (flavors==FLAVOR_NAMES[i])
                    model_phases[mask, chan] = linear(FLAVOR_LENGTHS[i]-150, **fit_gradient_dict)
                    mask = (flavors==FLAVOR_NAMES[i+3])
                    model_phases[mask, chan] = linear(FLAVOR_LENGTHS[i+3]-150, **fit_gradient_dict)*1.4

            # average over course channels
            # def least_squares(north_ramp, east_ramp, rg6_90_delay, rg6_150_delay, rg6_230_delay):
            #     return np.nansum((diff_angle-offset_and_flavor(north_ramp, east_ramp, rg6_90_delay, rg6_150_delay, rg6_230_delay)[:, None])**2)/ERROR**2

            # m = Minuit(least_squares, north_ramp=0, east_ramp=0,
            # rg6_90_delay=0,
            # rg6_150_delay=np.nanmedian(diff_angle[rg6_150]),
            # rg6_230_delay=np.nanmedian(diff_angle[rg6_230]))
            # m.migrad()

            # linear = lambda x, m, c: m*x + c
            # least_squares_cable = LeastSquares([90-REF_FLAVOR_LENGTH, 150-REF_FLAVOR_LENGTH, 230-REF_FLAVOR_LENGTH], 
            #                             [m.values['rg6_90_delay'], m.values['rg6_150_delay'], m.values['rg6_230_delay']],
            #                             [m.errors['rg6_90_delay'], m.errors['rg6_150_delay'], m.errors['rg6_230_delay']],
            #                             linear)


            # m_cable_delay = Minuit(least_squares_cable, m=0, c=0)
            # m_cable_delay.migrad()

            # for i in range(3):
            #     model_phases[flavors==FLAVOR_NAMES[i]] = linear(FLAVOR_LENGTHS[i]-150, **m_cable_delay.values.to_dict())
            #     model_phases[flavors==FLAVOR_NAMES[i+3]] = linear(FLAVOR_LENGTHS[i]-150, **m_cable_delay.values.to_dict())*1.4


            # PLOTTING
            # plot_phase_fits(obsid_solar, obsid_cal, freq, m, REF_FLAVOR_LENGTH, linear, m_cable_delay)

            # SAVE VALUES
            # fit_params.loc[i] = [obsid_solar, obsid_cal, freq, temp_diff, m.values['north_ramp'], m.values['east_ramp'], m.values['rg6_90_delay'], m.errors['rg6_90_delay'], m.values['rg6_150_delay'], m.errors['rg6_150_delay'], m.values['rg6_230_delay'], m.errors['rg6_230_delay'], m_cable_delay.values['m'], m_cable_delay.errors['m']]

            # TEMP ADJUST CALIBRATION SOLUTIONS
            solar_adjusted = np.zeros((1, cal_raw_cal.shape[0], cal_raw_cal.shape[1], 4), dtype=complex)
            cal_copy = cal_cal.copy()
            
            c = np.cos(model_phases)
            d = np.sin(model_phases)

            for i in range(4):

                a = cal_cal[1].data[0, :, :, i*2]
                b = cal_cal[1].data[0, :, :, i*2+1]

                solar_adjusted[0, :, :, i].real = a*c - b*d
                solar_adjusted[0, :, :, i].imag = a*d + b*c

                cal_copy[1].data[0, :, :, i*2] = solar_adjusted[0, :, :, i].real
                cal_copy[1].data[0, :, :, i*2+1] = solar_adjusted[0, :, :, i].imag

            cal_copy.writeto(f"obsids/{obsid_solar}/cal_sol_ch{freq}_sols_fine_160.fits", overwrite=True)


    # SAVE FIT PARAMS
    # file_name = args.list[:-4]
    # fit_params.to_csv(f'{file_name}_{freq}_fit_params.csv', index=False)
    # np.savetxt(f'{file_name}_{freq}_fits.txt', np.array(fit_gradients), delimiter=',')

if __name__ == "__main__":
    args = parse_args()
    main(vars(args))
