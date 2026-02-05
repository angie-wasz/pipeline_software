from astropy.io import fits
import argparse

def extract_slice(cal_fits, out_fits, channel_slice):
    # SOLUTIONS
    out_fits[1].data = cal_fits[1].data[:, :, channel_slice, :]
    # CHANBLOCKS
    out_fits[4].data = cal_fits[4].data[channel_slice]
    # RESULTS
    out_fits[5].data = cal_fits[5].data[:, channel_slice]
    return out_fits


def main(args):

	data = args['data']
	obs = args['obsid']
	start = args['start']
	stop = args['stop']
	channel = args['channel']

	print(f"{obs} Converting solutions")

	fits_tab = f"{data}/{obs}_sols.fits"
	cal_fits = fits.open(fits_tab)
	out_fits = cal_fits.copy()
	
	out_fits = extract_slice(cal_fits, out_fits, slice(start, stop))
	out_fits.writeto(f"{data}/{obs}_ch{channel}_sols.fits", overwrite=True)


if __name__ == '__main__':

	parser = argparse.ArgumentParser()
	parser.add_argument("-d", "--data", type=str, required=True, help="Data directory")
	parser.add_argument("-o", "--obsid", type=int, required=True, help="obsid")
	parser.add_argument("--start", type=int, default=640, help="Starting slice of wanted channels")
	parser.add_argument("--stop", type=int, default=704, help="Stopping slice (exclusive) of wanted channels")
	parser.add_argument("--channel", type=str, default='129-130', help="Name of selected channels, e.g. 129-130")
	args = parser.parse_args()
	
	main(vars(args))
