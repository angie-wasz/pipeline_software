#!/usr/bin/python
"""
Read a calibration solution binary file as produced by Andre Offringa's tools

These files are not documented outside the source code, but you can find the relevant code by grepping for WriteSolution.

The fit_complex_gains may be useful more widely so it is kept independent from tha aocal stuff.

It should never be necessary to import the AOClass itself, rather it can be returned from the fromfile and zeros functions.
"""
import sys, os, struct, logging, glob
from collections import namedtuple
import numpy as np

HEADER_FORMAT = "8s6I2d"
HEADER_SIZE = struct.calcsize(HEADER_FORMAT)
HEADER_INTRO = b"MWAOCAL\0"

Header = namedtuple("header", "intro fileType structureType intervalCount antennaCount channelCount polarizationCount timeStart timeEnd")
Header.__new__.__defaults__ = (HEADER_INTRO, 0, 0, 0, 0, 0, 0, 0.0, 0.0)

assert struct.calcsize("I") == 4, "Error, unexpected unsigned int size used by python struct"
assert struct.calcsize("c") == 1, "Error, unexpected char size used by python struct"
assert struct.calcsize("d") == 8, "Error, unexpected double size used by python struct"
if not sys.byteorder == 'little':
    logging.warn("byteorder=%s", sys.byteorder)
else:
    logging.debug("byteorder=%s", sys.byteorder)

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
        logging.warn("high variance detected in phases, check output model!")
    #finally do least squares
    m, c = np.polyfit(u_index, np.angle(u0), 1, w=np.abs(u)**-2)
    fit_complex = np.array(np.cos(v_index*m + c), dtype = np.complex128)
    fit_complex.imag =     np.sin(v_index*m + c)
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
        raise RuntimeError("clip not implemented")
    else:
        raise RuntimeError("mode %s not implemented" % mode)

class AOCal(np.ndarray):
    """
    AOCAl stored as a numpy array (with start and stop time stored as floats)

    Array is of dtype complex128 with the following dimensions:

    - calibration interval
    - antenna
    - channel
    - polarisation (order XX, XY, YX, YY)

    The following attributes are made available for convenience, however they
    are not stored explicitly, just read from the array shape.

    aocal.n_int
    aocal.n_ant
    aocal.n_chan
    aocal.n_pol
    """

    def __new__(cls, input_array, time_start=0.0, time_end=0.0):
        """
        See http://docs.scipy.org/doc/numpy-1.10.1/user/basics.subclassing.html
        """
        obj = np.asarray(input_array).view(cls)
        # add the new attribute to the created instance
        obj.time_start = float(time_start)
        obj.time_end = float(time_end)
        # Finally, we must return the newly created object:
        return obj

    def __array_finalize__(self, obj):
        if obj is None:
            return
        self.time_start = getattr(obj, 'time_start', None)
        self.time_end = getattr(obj, 'time_end', None)

    def __getattr__(self, name):
        if name == 'n_int':
            return self.shape[0]
        elif name == 'n_ant':
            return self.shape[1]
        elif name == 'n_chan':
            return self.shape[2]
        elif name == 'n_pol':
            return self.shape[3]
        elif name == 'time_start':
            # required to avoid infinite recursion
            return object.__getattribute__(self, time_start)
        elif name == 'time_end':
            # required to avoid infinite recursion
            return object.__getattribute__(self, time_end)
        else:
            raise AttributeError("AOCal has no Attribute %s. Dimensions can be accessed via n_int, n_ant, n_chan, n_pol" % name)

    def strip_edge(self, n_chan):
        """
        return a copy of the array with edge channels removed

        useful for printing without nans but don't write out as calibration solution!
        """
        return self[:, :, n_chan:-n_chan, :]

    def tofile(self, cal_filename):
        if not (np.iscomplexobj(self) and self.itemsize == 16 and len(self.shape) == 4):
            raise TypeError("array must have 4 dimensions and be of type complex128")
        header = Header(intervalCount=self.shape[0], antennaCount = self.shape[1], channelCount = self.shape[2], polarizationCount = self.shape[3], timeStart = self.time_start, timeEnd = self.time_end)
        with open(cal_filename, "wb") as cal_file:
            header_string = struct.pack(HEADER_FORMAT, *header)
            cal_file.write(header_string)
            logging.debug("header written")
            cal_file.seek(HEADER_SIZE, os.SEEK_SET) # skip header. os.SEEK_SET means seek relative to start of file
            np.ndarray.tofile(self, cal_file)
            logging.debug("binary file written")

    def fit(self, pols=(0, 3), mode='model', amp_order=5):
        if not (np.iscomplexobj(self) and self.itemsize == 16 and len(self.shape) == 4):
            raise TypeError("array must have 4 dimensions and be of type complex128")
        fit_array = np.zeros(self.shape, dtype=np.complex128)
        for interval in range(self.shape[0]):
            for antenna in range(self.shape[1]):
                logging.debug("fitting antenna %d" % antenna)
                for pol in pols:
                    v = self[interval, antenna, :, pol]
                    if sum(~np.isnan(self[interval, antenna, :, pol])) > 0:
                        self[interval, antenna, :, pol] = fit_complex_gains(self[interval, antenna, :, pol])

def ones(n_interval=1, n_antennas=128, n_channel=3072, n_pol=4, time_start=0.0, time_end=0.0):
    """
    produce an aocal with all complex gains set to amp 1, phase 0.
    """
    return AOCal(np.ones((n_interval, n_antennas, n_channel, n_pol), dtype=np.complex128), time_start, time_end)

def zeros(n_interval=1, n_antennas=128, n_channel=3072, n_pol=4, time_start=0.0, time_end=0.0):
    """
    produce an aocal with all complex gains set to amp 0, phase 0.
    """
    return AOCal(np.zeros((n_interval, n_antennas, n_channel, n_pol), dtype=np.complex128), time_start, time_end)

def fromfile(cal_filename):
    """
    Read AOCal from file.
    """
    with open(cal_filename, "rb") as cal_file:
        header_string = cal_file.read(struct.calcsize(HEADER_FORMAT))
        header = Header._make(struct.unpack(HEADER_FORMAT, header_string))
        logging.debug(header)
        assert header.intro == HEADER_INTRO, "File is not a calibrator file"
        assert header.fileType == 0, "fileType not recognised. Only 0 (complex Jones solutions) is recognised in mwatools/solutionfile.h as of 2013-08-30"
        assert header.structureType == 0, "structureType not recognised. Only 0 (ordered real/imag, polarization, channel, antenna, time) is recognised in mwatools/solutionfile.h as of 2013-08-30"
        logging.debug("header OK")

        count = header.intervalCount * header.antennaCount * header.channelCount * header.polarizationCount
        assert os.path.getsize(cal_filename) == HEADER_SIZE + 2*count*struct.calcsize("d"), "File is the wrong size."
        logging.debug("file correct size")
        cal_file.seek(HEADER_SIZE, os.SEEK_SET) # skip header. os.SEEK_SET means seek relative to start of file

        data = np.fromfile(cal_file, dtype=np.complex128, count=count)
    shape = [header.intervalCount, header.antennaCount, header.channelCount, header.polarizationCount]
    data = data.reshape(shape)
    new_aocal = AOCal(data, header.timeStart, header.timeEnd)
    return new_aocal

def rtsfile(metafitsfile, rts_filename_pattern="DI_JonesMatrices_node[0-9]*.dat"):
    import astropy.io.fits as fits

    """
    Read DI Jones matrices from RTS output files and convert to "aocal" format.
    Assumes RTS solutions are one per coarse channel.
    Needs the associated metafits file to get the antenna ordering right.
    """
    # (Relative) comparison of RTS and OFFRINGA polarisation ordering:
    # OFFRINGA:  XX-R  XX-I  XY-R  XY-I  YX-R  YX-I  YY-R  YY-I
    # RTS:       YY-R  YY-I  YX-R  YX-I  XY-R  XY-I  XX-R  XX-R
    pol_map = [3, 2, 1, 0]

    # Antenna reording:
    hdu = fits.open(metafitsfile)
    ant_map = hdu['TILEDATA'].data['Antenna'][::2] # only want each tile once
    hdu.close()

    # Assumptions:
    nintervals = 1
    npols = 4

    # Get file names
    rts_filenames = sorted(glob.glob(rts_filename_pattern)) # <-- Assumes file names are appropriately ordered by channel
    rts_filenames.reverse()
    nchannels = len(rts_filenames)

    for chan in range(len(rts_filenames)):
        rts_filename = rts_filenames[chan]
        with open(rts_filename, "r") as rts_file:
            Jref = float(rts_file.readline()) # Common factor of all gains is a single number in the first line of the file
            rts_file.readline() # The second line contains the model primary beam Jones matrix (in the direction of the calibrator)
            lines = rts_file.readlines()

            # If first time through, get number of antennas and set up data array for solution
            if chan == 0:
                nantennas = len(lines)
                # Create numpy array structure
                data = np.empty((nintervals, nantennas, nchannels, npols,),dtype=np.complex128)
                data[:] = np.nan
            else:
                assert len(lines) == nantennas, "Files contain different numbers of antennas"

            # Parse each line
            for ant in range(len(lines)):
                line = lines[ant]
                jones_str = line.split(",")
                assert len(jones_str) == 2*npols, "Incorrect number of elements in Jones matrix"
                ant_idx = ant_map[ant]
                for pol in range(len(pol_map)):
                    p = pol_map[pol]
                    data[0,ant_idx,chan,pol] = float(jones_str[2*p]) + float(jones_str[2*p+1])*1j

    new_aocal = AOCal(data, 0, 0)
    return new_aocal
