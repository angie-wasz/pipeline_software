FREQ=121-132
PIPELINE=${scripts_dir}
CAT_PATH=/software/projects/mwasci/awaszewski/catalogs/

SUFFIX=gleam
RA=RAJ2000
DE=DEJ2000
HDF5=${OBSID}.hdf5

SH=/bin/bash
PYTHON=python

GLEAM_TARGET : $(OBSID)_$(SUFFIX)_digest.fits

$(OBSID)_${SUFFIX}_digest.fits : $(OBSID)_$(SUFFIX).vot 
	$(SH) $(PIPELINE)/make_digest_newcols.sh  $(OBSID)_$(SUFFIX).vot $(OBSID)_${SUFFIX}_digest.fits

$(OBSID)_no_${SUFFIX}.vot : $(OBSID)_infield_$(SUFFIX).vot $(OBSID)_$(FREQ)_image_corr.vot
	bash $(PIPELINE)/nomatch.sh $(OBSID)_infield_$(SUFFIX).vot $(OBSID)_$(FREQ)_image_corr.vot $(OBSID)_no_$(SUFFIX).vot

$(OBSID)_no_${SUFFIX}_moment2.vot : $(OBSID)_infield_$(SUFFIX).vot $(OBSID)_$(FREQ)_image_moment2_corr.vot
	bash $(PIPELINE)/nomatch.sh $(OBSID)_infield_$(SUFFIX).vot $(OBSID)_$(FREQ)_image_moment2_corr.vot $(OBSID)_no_$(SUFFIX)_moment2.vot

$(OBSID)_$(SUFFIX).vot : $(OBSID)_detections_$(SUFFIX).vot
	$(PYTHON) $(PIPELINE)/add_nsi2.py $(OBSID)_detections_$(SUFFIX).vot $(OBSID)_$(SUFFIX).vot --ra_col=$(RA) --dec_col=$(DE)

$(OBSID)_detections_$(SUFFIX).vot : $(OBSID)_infield_$(SUFFIX).vot $(OBSID)_$(FREQ)_image_corr.vot $(OBSID)_$(FREQ)_image_moment2_corr.vot
	$(SH) $(PIPELINE)/match_master.sh  $(OBSID)_infield_$(SUFFIX).vot $(OBSID)_$(FREQ)_image_corr.vot $(OBSID)_$(FREQ)_image_moment2_corr.vot $(OBSID)_detections_$(SUFFIX).vot $(RA) $(DE)

$(OBSID)_infield_$(SUFFIX).vot : $(HDF5)
	$(PYTHON) $(PIPELINE)/make_obs_cat.py $(HDF5) $(CAT_PATH)/ips_gleam_vlssr_dr2_230802.fits $(OBSID)_infield_$(SUFFIX).vot --ra_col=$(RA) --dec_col=$(DE)
