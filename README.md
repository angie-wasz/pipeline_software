# pipeline_software

This is the brand new repo that has all the scripts (and some of the catalogs) required to run the calibration (still in testing) and imaging pipelines on Garrawarla.

Excluded is the container (ips_post.img) that handles the post imaging part of the pipeline
Also excluded is the GLEAM catalog hdf5 (as it is too large, but I have a copy stored on mwa-solar)

All the imaging scripts are on here, including
-> processing scripts
-> slurm script creators
-> control of the pipeline (submission of jobs and comms with the database)

Also included are the ips_continuum fits file and the GGSM_updated fits file 

This is subject to change, but also has these calibration scripts
-> control of the pipeline (submission of jobs and comms with the database)
