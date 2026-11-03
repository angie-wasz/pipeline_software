import os, sys, datetime, h5py, contextlib
import numpy as np
from optparse import OptionParser
from astropy.io import fits

CACHE_SIZE = 1024
TIME_INTERVAL = 0.5
TIME_INDEX = 0
POLS = 'XX,YY'
SUFFIXES = "image"
N_CHANNELS = 2
#N_TIMESTEPS = 496
N_TIMESTEPS = 494
SLICE = [0, 0, slice(None, None, None), slice(None, None, None)]
FILENAME = "{obsid}_{band}_ds_standard-t{time:04d}-{chan:04d}-{pol}-{suffix}.fits"

parser = OptionParser(usage="usage: obsid" +
                      """
                          Convert a set of wsclean images into an hdf5 image cube
                      """)
parser.add_option("-n", default=N_TIMESTEPS, dest="n", type="int", help="number of timesteps to process [default: %default]")
parser.add_option("--start", default=TIME_INDEX, dest="start", type="int", help="starting time index [default: %default]")
parser.add_option("--step", default=TIME_INTERVAL, dest="step", type="float", help="time between timesteps [default: %default]")
parser.add_option("--outfile", default=None, dest="outfile", type="str", help="outfile [default: [obsid].hdf5]")
parser.add_option("--suffixes", default=SUFFIXES, dest="suffixes", type="str", help="comma-separated list of suffixes to store [default: %default]")
parser.add_option("--bands", default=None, dest="bands", type="str", help="comma-separated list of contiguous frequency bands [default None]")
parser.add_option("--pols", default=POLS, dest="pols", type="str", help="comma-separated list of pols [default: %default]")

opts, args = parser.parse_args()

obsid = args[0]

if os.path.exists(opts.outfile):
    file_mode = "r+"
else:
    file_mode = "w"

opts.suffixes = opts.suffixes.split(',')
opts.pols = opts.pols.split(',')
if opts.bands is None:
    opts.bands = [None]
else:
    opts.bands = opts.bands.split(',')

propfaid = h5py.h5p.create(h5py.h5p.FILE_ACCESS)
settings = list(propfaid.get_cache())
settings[2] *= CACHE_SIZE
propfaid.set_cache(*settings)

with contextlib.closing(h5py.h5f.create(opts.outfile.encode("utf-8"), fapl=propfaid)) as fid:
    df = h5py.File(fid, file_mode)
df.attrs['VERSION'] = '0.2'
df.attrs['USER'] = os.environ['USER']
df.attrs['DATE_CREATED'] = datetime.datetime.utcnow().isoformat()

for band in opts.bands:
	if band is None:
		group = df['/']
	elif band not in df.keys():
		group = df.create_group(band)
	else:
		group = df[band]
	group.attrs['TIME_INTERVAL'] = opts.step

	image_file = FILENAME.format(obsid=obsid, band=band, time=opts.start, chan=opts.start, pol=opts.pols[0], suffix=opts.suffixes[0])

	hdus = fits.open(image_file, memmap=True)
	image_size = hdus[0].data.shape[-1]
	data_shape = [len(opts.pols), image_size, image_size, N_CHANNELS, opts.n]
	chunks = (len(opts.pols), 16, 16, N_CHANNELS, opts.n)

	pb_mask = np.ones(data_shape[1:-1] + [1], dtype=bool)
	pb_nan = np.ones(data_shape[1:-1] + [1])

	timestep_start = group.create_dataset("timestep_start", (opts.n,), dtype=np.uint16)
	timestep_stop = group.create_dataset("timestep_stop", (opts.n,), dtype=np.uint16)
	timestamp = group.create_dataset("timestamp", (opts.n,), dtype="S21")
	header_file = FILENAME.format(obsid=obsid, band=band, time=opts.n//2, chan=0, pol=opts.pols[0], suffix=opts.suffixes[0])
	hdus = fits.open(header_file, memmap=True)
	header = group.create_dataset('header', data=[], dtype=np.float16)
	for key, item in hdus[0].header.items():
		header.attrs[key] = item

	for s, suffix in enumerate(opts.suffixes):
		if s == 0:
			data = np.empty(data_shape, dtype=np.float16)
		else:
			data *= 0
		filenames = group.create_dataset("%s_filenames" % suffix, (len(opts.pols), N_CHANNELS, opts.n), dtype="S%d" % len(header_file), compression='lzf')

		n_rows = image_size
		i = 0
		for t in range(opts.n):
			
			im_slice = [slice(n_rows*i, n_rows*(i+1)), slice(None, None, None)]
			fits_slice = SLICE[:-2] + im_slice

			for chan in range(N_CHANNELS):
				for p, pol in enumerate(opts.pols):
					
					infile = FILENAME.format(obsid=obsid, band=band, time=t+opts.start, chan=chan, pol=pol, suffix=suffix)
					hdus = fits.open(infile, memmap=True)
					filenames[p, chan, t] = infile.encode("utf-8")
					data[p, n_rows*i:n_rows*(i+1), :, chan, t] = np.where(pb_mask[n_rows*i:n_rows*(i+1), :, chan, 0],
                                                                   hdus[0].data[tuple(fits_slice)],
                                                                   np.nan)*pb_nan[n_rows*i:n_rows*(i+1), :, chan, 0]
					
					if s == 0 and p == 0 and chan == 0:
						timestamp[t] = hdus[0].header['DATE-OBS'].encode("utf-8")
						timestep_start[t] = t
						timestep_stop[t] = t+1

		hdf5_data = group.create_dataset(suffix, data_shape, chunks=chunks, dtype=np.float16, compression='lzf', shuffle=True)
		hdf5_data[...] = data
