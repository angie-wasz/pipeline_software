"""
This module provides a script removing extra columns after making an acceptable compression. COPY_DATA will be removed. DATACOL can be a list to be removed. COPY_ADIOS is then the reference.

Usage:
  python strip_cols.py [--filename DIR] [--datacol=CORRECTED_DATA]
"""
import argparse
import array
import json
import sys

import functools
import operator
import os, time, shutil
from matplotlib import pyplot as plt

from casacore.tables import (
  makearrcoldesc,
  makescacoldesc,
  table,
  maketabdesc,
  makedminfo)
import numpy as np
import adios2
from contextlib import contextmanager
from math import sqrt

DELETEOLD=True
DATACOL='None'
FILENAME='demo.ms'

def run(DATACOL=DATACOL,FILENAME=FILENAME)-> tuple:
  """Write and read the table and create a copy of the DATA column from the DATA
  """
  tb=table(FILENAME,readonly=False)

  print(f"  MS File: {FILENAME} will remove requested {DATACOL} columns")
  print()


  print('Remove these data columns: ',DATACOL)
  #tb.removecols('COPY_DATA')
  for DC in DATACOL.split(','):
          if DC in tb.colnames():
              a_seq=tb.getdminfo(DC)["SEQNR"]
              tb.removecols(DC)
              # ADIOS does not remove old files after deletion
              if os.path.isdir(f'{FILENAME}/table.f{a_seq}.bp'): shutil.rmtree(f'{FILENAME}/table.f{a_seq}.bp')
              print(f'{DC} - removed')
          else:
              print(f'No {DC} - not removing that')
      
  tb.close()


  HISTORY=True
  if HISTORY==True:
    import time
    tb=table(FILENAME+'/HISTORY',readonly=False)
    n=tb.nrows() #n=-1 # Stick remarks at the end. Could loose important info ..
    tb.addrows(nrows=1)
    #d=t2.getcol('CLI_COMMAND')#,nrow=(t2.nrows()-1))
    #n=d['shape'];n[0]+=1;d['shape']=n
    #for n in range(d['shape'][0]):
    #  if d['array'][n]=='': break
    #d['array'][n]=' '.join(sysargvIn)
    #t2.putcol('CLI_COMMAND',d)
    d=tb.getcol('TIME')
    mjd=time.time()/3600/24 +40588-0.5  # Convert 01/01/1970 to MJD
    d[n]=mjd
    tb.putcol('TIME',d)
    d=tb.getcol('MESSAGE')
    d[n]=f'Removed COPY_DATA and {DATACOL}'
    tb.putcol('MESSAGE',d)
    d=tb.getcol('ORIGIN')
    d[n]=sys.argv[0]#+':'+k[-1]
    tb.putcol('ORIGIN',d)
    tb.close()
  
if __name__ == "__main__":  
  parser = argparse.ArgumentParser(description=
                                   'Remove the extra columns after compression')
  parser.add_argument("--filename", type=str, default=FILENAME, help="MS filename")
  parser.add_argument("--datacol", type=str, default=DATACOL, help="Data Column")

  DELETEOLD=True
  DATACOL='None'
  args = parser.parse_args()
  if args.filename != FILENAME: 
    FILENAME = args.filename
  if args.datacol != DATACOL: 
    DATACOL = args.datacol

  run(DATACOL=DATACOL,FILENAME=FILENAME)
  sys.exit()
  
