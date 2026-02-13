import os, argparse
import numpy as np

import astropy.units as u
from astropy.time import Time
from astropy.io import votable
from astropy.coordinates import SkyCoord
from sunpy.coordinates import Helioprojective

import matplotlib.pyplot as plt
import matplotlib.colors as col

plt.rcParams["font.family"] = "Nimbus Roman"
plt.rcParams['font.size'] = 15
plt.rcParams["mathtext.fontset"] = "stixsans"

median = 1.0
vmax = 3.0
vmin = median**2/vmax
norm = col.LogNorm(vmin=vmin, vmax=vmax)

cm = plt.get_cmap('PRGn')

def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument('-o', '--obsid', type=int, required=True)
    parser.add_argument('-d', '--dir', type=str, required=True)
    args = parser.parse_args()

    if len(str(args.obsid)) < 10:
        parser.error("Invalid OBSID, incorrent length")

    if not os.path.isdir(args.dir):
        parser.error(f"Invalid directory, {args.dir} does not exist")

    return args

def convert_to_solar(ra, dec, obstime):
    radec = SkyCoord(ra*u.deg, dec*u.deg, distance=1e9*u.parsec)
    helio = radec.transform_to(Helioprojective(obstime=obstime, observer='Earth'))
    return helio.Tx.deg, helio.Ty.deg

def votable_to_pandas(votable_file):
    vo = votable.parse(votable_file)
    table = vo.get_first_table().to_table(use_names_over_ids=True)
    return table.to_pandas()

def filtering_df(df):
    df = df[(df.snr_scint > 2)].reset_index(drop=True)
    df = df[(df.g > 0)].reset_index(drop=True)
    return df

def main():
    args = parse_args()

    obs = args.obsid
    dir = args.dir

    print(f"Generating g-map for {obs}")

    obstime = Time(obs, format='gps')

    # create the gmap
    fig, ax = plt.subplots(1,1, figsize=(6,5), dpi=150)
    ax.set_aspect('equal')
    ax.set_xlabel(r'$\theta _x$ [deg]')
    ax.set_ylabel(r'$\theta _y$ [deg]')
    ax.set_facecolor('gainsboro')
    ax.set_title(f"{obstime.iso}")

    # g-level
    TAB = f"{dir}/{obs}_glevel_simplify.vot"
    if not os.path.exists(TAB):
        print(f"ERROR: g-level data table {TAB} does not exist")
        exit(1)
    df = filtering_df(votable_to_pandas(TAB))

    ra, dec, g = df.RAJ2000_1.to_numpy(), df.DEJ2000_1.to_numpy(), df.g.to_numpy()
    tx, ty = convert_to_solar(ra, dec, obstime)
    
    ax.set_xlim([min(tx)-10, max(tx)+10])
    ax.set_ylim([min(ty)-10, max(ty)+10])

    print(f"Number of sources with g-level: {len(g)}")
    
    ax.scatter(0,0, marker='*', c='tab:orange', s=100)
    field = ax.scatter(tx, ty, c=g, marker='o',
                        cmap=cm,
                        norm=norm,
                        s=20,
                        edgecolors='dimgrey',
                        linewidths=0.2)
    
    bar = plt.colorbar(field, ax=ax, pad=0.01, label='g-level')
    bar.minorticks_off()
    bar.set_ticks([vmin, median, vmax])
    bar.set_ticklabels(["{:.1f}".format(vmin), "{:.1f}".format(median), "{:.1f}".format(vmax)])

    print("Done, saving as .png")

    fig.tight_layout()
    fig.savefig(f'{dir}/{obs}_gmap.png', bbox_inches='tight')
    plt.close()

if __name__ == '__main__':
    main()
