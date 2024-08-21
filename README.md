# pipeline_software

This is the brand new repo that has all the scripts (and some of the catalogs) required to run the calibration (not included yet) and imaging pipelines on Garrawarla.

Excluded is the container (ips_post.img) that handles the post imaging part of the pipeline
Also excluded is the GLEAM catalog hdf5 (as it is too large, but I have a copy stored on mwa-solar)

Right now I haven't included the calibration start scripts, they are still on the old repo and I'll get to them when I need to calibrate something again

All the imaging scripts are on here, including
-> processing scripts
-> slurm script creators
-> control of the pipeline (submission of jobs and comms with the database)

Also included are the ips_continuum fits file and the GGSM_updated fits file 
