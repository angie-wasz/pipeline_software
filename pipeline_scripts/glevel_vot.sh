OBSID=$1
DATA=$2

catalog="/software/projects/mwasci/awaszewski/catalogs/ips_dr2_250108.fits"

# Creates a cross match between the IPS DR2 catalog and the source catalogue from the images
topcat -stilts tmatch2 out=${DATA}/cross_match.fits ofmt=fits matcher=exact values1=GLEAM values2=GLEAM join=1and2 find=best1 in1=${DATA}/${OBSID}_gleam_digest.fits in2=${catalog}

# Creates the big glevel table
topcat -stilts tpipe cmd='addcol g dS2/(peak_flux*mpt1*nsi_fit)' cmd='addcol snr_g nsi_fit*mpt1*peak_flux/local_rms2' cmd='addcol demon square(peak_flux*mpt1*nsi_fit)' omode=out ofmt=vot out=${DATA}/${obsid}_glevel.vot in=${DATA}/cross_match.fits

# add in temp columns
topcat -stilts tpipe cmd='addcol dS2_err (mpt1*peak_flux*nsi_fit/demon)*local_rms2' cmd='addcol flux_err (-mpt1*dS2*nsi_fit/demon)*local_rms' cmd='addcol n_err (-mpt1*dS2*peak_flux/demon)*nsi_err' omode=out ofmt=vot out=${DATA}/${OBSID}_glevel.vot in=${DATA}/${OBSID}_glevel.vot

# actual g-error
topcat -stilts tpipe cmd='addcol g_err sqrt(square(dS2_err)+square(flux_err)+square(n_err))' omode=out ofmt=vot out=${DATA}/${OBSID}_glevel.vot in=${DATA}/${OBSID}_glevel.vot

# Creates a simplied glevel table as well for quicker gmap creation
topcat -stilts tpipe cmd='delcols "s_162_1 mpt1 mpt2 pbcor pbcor_norm ra_corr dec_corr peak_flux local_rms snr ra_corr_2 dec_corr_2 dS snr_2 Separation_2 dS2 local_rms2 GLEAM_2 RAJ2000_2 DEJ2000_2 s_162_2 elongation class ul_fit ul_err l_0 l_1 s_cont_lim s_5lim n_fit n_eff demon dS2_err flux_err n_err"' omode=out ofmt=vot out=${DATA}/${OBSID}_glevel_simplify.vot in=${DATA}/${OBSID}_glevel.vot
