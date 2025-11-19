#!/usr/bin/env python
import os, logging
from optparse import OptionParser #NB zeus does not have argparse!
import warnings
import numpy as np
import aocal

# switch off annoying warnings
with warnings.catch_warnings():
    warnings.filterwarnings('ignore', r'All-NaN (slice|axis) encountered')

if __name__ == '__main__':
    parser = OptionParser(usage = "usage: %prog infile outfile" +
    """
    interpolate/average to a larger/smaller number of channels.

    If both are set, average will be done first to allow some crude smoothing, but this has not been extensively tested, and may degrade channels at the edge of the range.

    """)
    parser.add_option("-i", "--interpolate_factor", type="int", default=None, metavar="FACTOR", dest="interp", help="increase number of chans by FACTOR")
    parser.add_option("-a", "--average_factor", type="int", default=None, metavar="FACTOR", dest="average", help="decrease number of chans by FACTOR")
    opts, args = parser.parse_args()

    if len(args) != 2:
        parser.error("incorrect number of arguments")

    if opts.interp is None and opts.average is None:
        parser.error("interpolate or average must be set")

    incal = aocal.fromfile(args[0])
    if opts.average is not None:
        if incal.n_chan % opts.average:
            raise ValueError("n_chan %d is not divisible by averaging factor %d" % (incal.n_chan, opts.average))
        outcal = np.nanmean(incal.reshape(incal.n_int, incal.n_ant, -1, opts.average, incal.n_pol), axis=3)

    if opts.interp is not None:
        outcal = aocal.ones(incal.n_int, incal.n_ant, incal.n_chan*opts.interp, incal.n_pol, incal.time_start, incal.time_end)
        n = incal.n_chan
        in_x = np.arange(incal.n_chan)
        out_x = np.linspace(-0.5 + 1.0/opts.interp/2, incal.n_chan - 0.5 - 1.0/opts.interp/2, incal.n_chan*opts.interp)
        for i in range(incal.n_int):
            for a in range(incal.n_ant):
                for p in range(incal.n_pol):
                    #np.interp *should* work with complex, but it doesn't
                    real_interp = np.interp(out_x, in_x, incal[i, a, :, p].real)
                    imag_interp = np.interp(out_x, in_x, incal[i, a, :, p].imag)
                    outcal[i, a, :, p].real = real_interp
                    outcal[i, a, :, p].imag = imag_interp
    outcal.tofile(args[1])
