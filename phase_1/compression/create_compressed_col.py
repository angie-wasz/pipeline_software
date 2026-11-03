"""
This module provides a test script for evaluating the performance and accuracy of column-wise compression
using the Adios2StMan storage manager in casacore tables. It generates synthetic complex data, writes it to
a table with configurable compression settings for the real and imaginary parts, and measures the compression
ratio and read/write times. The script also supports plotting the difference between original and compressed
data for visual inspection.

Key Features:
- Configurable compressor and accuracy for each column via command-line arguments.
- Synthetic data generation with user-defined shape.
- Writes original, real, and imaginary parts to separate columns with optional compression.
- Measures and prints compression ratios and timing statistics for write and read operations.
- Optionally plots histograms of differences between original and compressed data.

Dependencies:
- casacore.tables
- numpy
- adios2 (with mgard, sz and zfp)
- matplotlib

Usage:
  python create_compressed.py [--compressor COMP] [--accuracy ACC] [--filename DIR]
"""
import argparse
import array
import json
import sys
import time # why is this failing?

import functools
import operator
import os, time, shutil
from matplotlib import pyplot as pl

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

def find_smallest_divisor(num:int) -> int:
    """Find the smalles divisor of num greater or equal to 3.

    Args:
        num (int): The number to be considered

    Returns:
        int: The smallest number >=3 that divides num withoput rest.
  """
    for i in range(3, int(sqrt(num)) + 1):
        if num % i == 0:
            return i
    return num

def get_size(msdir):
    size = os.path.getsize(msdir)
    for root, dirs, files in os.walk(msdir):
        size += sum(os.path.getsize(os.path.join(root, name))
                    for name in files + dirs)
    return size

# various settings
COMPRESSORS = ["mgard", "mgard_complex", "zfp", "sz", "dysco",  "None"];
COMPRESSOR = "mgard";
LOSS = ['huffman_zstd','huffman','test']# last is not a valid response
LOSSLESS = LOSS[0]
MODE = 'ABS';
ACCURACY = "0.1";
FILENAME = "1197634368.ms";
DATACOL = "CORRECTED_DATA";
DELETEOLD = True
PLOT = False
STEPS = 0

def make_DYSCO_column(DATACOL=DATACOL,FILENAME=FILENAME,
        STEPS=STEPS,bitcount=ACCURACY, DELETEOLD=DELETEOLD)-> tuple:
  """
  Just to keep the information how this would have to be done. DYSCO requires the table
  to have ANTENNA1, ANTENNA2, FIELD and DATA tables.
  The given FILENAME and DATACOL will be encoded as COPY_DYSCO and then COPY_DATA
  """

  import time
  # if FILENAME = string (else assume it is an open tab)
  tb=table(FILENAME,readonly=False)
  try:
      print(f'Opening data column {DATACOL}')
      SHAP=np.array(tb.getcol(DATACOL,nrow=1).shape)
  except:
      #print('No datacolumn %s trying "DATA"'%(DATACOL))
      DATACOL = 'DATA'
      print(f'Opening data column {DATACOL}')
      SHAP=np.array(tb.getcol(DATACOL,nrow=1).shape)
  SHAP[0]=tb.nrows()
  size = functools.reduce(operator.mul, SHAP[1:], SHAP[0] * 8)

  print("Settings:")
  print(f"  Compressor for {DATACOL} column: {COMPRESSOR} (Accuracy: {ACCURACY})")
  print(f"  Data shape: {SHAP}")
  print(f"  MS File: {FILENAME}")
  print()

  cell_shape=SHAP[1:]
  Atabdesc = makearrcoldesc("COPY_DYSCO", np.complex64(0+0j), shape=SHAP[1:], options=1,
                               datamanagertype='DyscoStMan')
  Atabdesc['desc']['valueType']='complex' # bug in Dysco???
  Adminfo={ "TYPE": "DyscoStMan", "NAME": "dysco", "SPEC": {
                          'dataBitCount': int(bitcount),
                          'weightBitCount': 12,
                          'distribution': 'TruncatedGaussian',
                          'normalization': 'AF',
                          'studentTNu': 0.0,
                          'distributionTruncation': 2.5
                      }
                  }
  group1=int(np.random.random()*1e4)
  group1=f'group{group1:%04d}'
  print(f'Using {group1} for labels')
  Ttabdesc = maketabdesc(
        (makearrcoldesc('COPY_DATA', '',
            valuetype='complex', shape=cell_shape,
            datamanagergroup=group1, datamanagertype='TiledShapeStMan' ),
         ))
  Tdminfo = makedminfo(
        Ttabdesc,
        {
            group1: {
                'OPERATORPARAMS': {
                    'COPY_DATA': {}
               } } } )

  if 'COPY_DYSCO' in tb.colnames():
    if DELETEOLD:
      print('Remove old dysco COPY')
      a_seq=tb.getdminfo("COPY_DYSCO")["SEQNR"]
      tb.removecols('COPY_DYSCO')
      print(f'Removing {FILENAME}/table.f{a_seq}')
      if os.path.isfile(f'{FILENAME}/table.f{a_seq}'): shutil.rmtree(f'{FILENAME}/table.f{a_seq}')
      tb.addcols(Atabdesc,dminfo=Adminfo)
    else:
      print('Reusing old dysco COPY')
  else:
      tb.addcols(Atabdesc,dminfo=Adminfo)
      
  if 'COPY_DATA' in tb.colnames():
    if DELETEOLD:
      print('Remove old standard COPY_DATA')
      #t_seq=tb.getdminfo("COPY_DATA")["SEQNR"]
      tb.removecols('COPY_DATA')
      #print(f'Removing {FILENAME}/table.f{t_seq}_TSM1')
      #shutil.rmtree(f'{FILENAME}/table.f{t_seq}_TSM1')
      tb.addcols(Ttabdesc,dminfo=Tdminfo)
    else:
      print('Reusing old DATA COPY')
  else:
      tb.addcols(Ttabdesc,dminfo=Tdminfo)

  if STEPS: # not equal zero
    steps=STEPS
    Nbase=int(SHAP[0]/steps)
    if steps<0:
        steps=len(np.unique(tb.getcol('TIME')))
        Nbase=int(SHAP[0]/steps)
        if (Nbase*steps!=SHAP[0]):
            steps = find_smallest_divisor(SHAP[0])    
            Nbase=SHAP[0]/steps
    print(f'Using {steps} steps to write and read new columns in steps of {Nbase}.')
  else:
    steps=1
    Nbase=SHAP[0]
    print(f'Using one step for writing and reading new columns.')
  tot_tic = time.time()
  for n in range(steps):
    print('Write %d/%d\t'%(n,steps))
    tic=time.time()
    vis=tb.getcol(DATACOL,nrow=Nbase,startrow=n*Nbase)
    tsteps = time.time()-tic
    print(f'Read {Nbase} complex visibilities from {DATACOL} column in {tsteps:.3f}s')
    s=vis.shape
    if True: #(COMPRESSOR == "mgard_complex")|(COMPRESSOR == "mgard"):
        vis=vis.reshape(-1)
        Inan=np.where(np.isnan(vis)==True)[0]
        vis[Inan]=0
        vis=vis.reshape(s)
    tic = time.time()
    tb.putcol('COPY_DYSCO',vis,nrow=Nbase,startrow=n*Nbase)
    tsteps = time.time()-tic
    print(f'Wrote {Nbase} compressed complex visibilities to DYSCO column in {tsteps:.3f}s')
  tb.close()
  tsteps = time.time()-tot_tic
  if (steps>1): print(f'Total Read/Write compressed complex visibilities from {DATACOL}/COPY_DYSCO column in {tsteps:.3f}s')

  tb=table(FILENAME,readonly=False)
  tot_tic = time.time()
  for n in range(steps):
    print('Read %d/%d\t'%(n,steps))
    #tic=time.time()
    #data=t.getcol('COPY_DATA',nrow=Nbase,startrow=n*Nbase)
    #tsteps = time.time()-tic
    #print(f'Read {Nbase} complex visibilities from COPY_DATA column in {tsteps:.3f}s')
    tic=time.time()
    vis=tb.getcol('COPY_DYSCO',nrow=Nbase,startrow=n*Nbase)
    tsteps = time.time()-tic
    print(f'Read {Nbase} compressed complex visibilities from COPY_DYSCO column in {tsteps:.3f}s')
    if np.mod(n,10)==0: # every 10th now
        data=tb.getcol(DATACOL,nrow=Nbase,startrow=n*Nbase)
        a1=tb.getcol('ANTENNA1',nrow=Nbase,startrow=n*Nbase)
        a2=tb.getcol('ANTENNA2',nrow=Nbase,startrow=n*Nbase)
        I=np.where(a1!=a2)[0]
        tic=np.nanstd(data[I])
        data-=vis
        try:
            print('Data Difference:',np.nanmax(np.abs(data[I])),np.nanstd(data[I]),'StdDev',tic)
        except:
            print('Data Difference - Failed')
    tic = time.time()
    tb.putcol('COPY_DATA',vis,nrow=Nbase,startrow=n*Nbase)
    tsteps = time.time()-tic
    print(f'Wrote {Nbase} complex visibilities to TILED column in {tsteps:.3f}s')
  a_seq=tb.getdminfo("COPY_DYSCO")["SEQNR"]
  t_seq=tb.getdminfo("COPY_DATA")["SEQNR"]
  tb.close()
  tsteps = time.time()-tot_tic
  if (steps>1): print(f'Total Read/Write compressed complex visibilities from COPY_DYSCO/COPY_DATA column in {tsteps:.3f}s')

  t_on_disk_size = get_size(f'{FILENAME}/table.f{t_seq}_TSM1')
  a_on_disk_size = get_size(f'{FILENAME}/table.f{a_seq}')
  rat_on_disk_size=100.*a_on_disk_size/t_on_disk_size
  print(f'Native size: {t_on_disk_size} Compressed size: {a_on_disk_size} or {rat_on_disk_size:.1f}%')
  #print(f'ORIG write time: {tnocomp_complex:.3f}')
  #print(f'REAL[{COMPRESSOR1}] compression and write time: {tcomp_real:.3f}')
  #print(f'IMAG[{COMPRESSOR2}] compression and write time: {tcomp_imag:.3f}\n')
  #print('Total compression and write time: '
  #      f'{(tcomp_real+tcomp_imag):.3f} ({((tcomp_real+tcomp_imag)/tnocomp_complex):.1f}x)\n\n')
  #
  #print(f'ORIG read time: {(tread_complex):.3f} s')
  #print(f'REAL[{COMPRESSOR1}] decompression and read time: {(tdecomp_real):.3f} s')
  #print(f'REAL compression ratio: {size / r_on_disk_size:.2f}')
  #print(f'IMAG[{COMPRESSOR2}] decompression and read time: {(tdecomp_imag):.3f} s')
  #print(f'IMAG compression ratio: {size / i_on_disk_size:.2f}\n')
  #print('Total decompression and read time: '
  #      f'{(tdecomp_real+tdecomp_imag):.3f} s ({((tdecomp_real+tdecomp_imag)/tread_complex):.1f}x)\n\n')
  #if PLOT:
  #  plot(vis, visr, visi, cvis)
  #
  HISTORY=True
  if HISTORY==True:
    import time
    tb=table(f"{FILENAME}/HISTORY",readonly=False)
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
    d[n]=f'Applied compressor {COMPRESSOR} with accuracy {ACCURACY} to make COPY_DYSCO (and then COPY_DATA) from {DATACOL}'
    print('Writing HISTORY: ',d[n])
    tb.putcol('MESSAGE',d)
    d=tb.getcol('ORIGIN')
    d[n]=sys.argv[0]#+':'+k[-1]
    tb.putcol('ORIGIN',d)
    d=tb.getcol('ORIGIN')
    d[n]=sys.argv[0]#+':'+k[-1]
    tb.putcol('ORIGIN',d)
    tb.close()
  
def run(DATACOL=DATACOL,FILENAME=FILENAME,
        STEPS=STEPS,ACCURACY=ACCURACY,COMPRESSOR=COMPRESSOR,LOSSLESS=LOSSLESS,
        DELETEOLD=DELETEOLD,PLOT=PLOT)-> tuple:
  """Write and read the table and create a copy of the DATA column from the DATA
  """
  
  import time
  tb=table(FILENAME,readonly=False)
  try:
      print(f'Opening data column {DATACOL}')
      SHAP=np.array(tb.getcol(DATACOL,nrow=1).shape)
  except:
      #print('No datacolumn %s trying "DATA"'%(DATACOL))
      DATACOL = 'DATA'
      print(f'Opening data column {DATACOL}')
      SHAP=np.array(tb.getcol(DATACOL,nrow=1).shape)
  SHAP[0]=tb.nrows()
  size = functools.reduce(operator.mul, SHAP[1:], SHAP[0] * 8)

  print("Settings:")
  print(f"  Compressor for {DATACOL} column: {COMPRESSOR} (Accuracy: {ACCURACY})")
  print(f"  Lossless: {LOSSLESS},  Data shape: {SHAP}")
  print(f"  MS File: {FILENAME}")
  print()

  cell_shape=SHAP[1:]
  Atabdesc = maketabdesc(
        (makearrcoldesc('COPY_ADIOS', '',
            valuetype='complex', shape=cell_shape,
            datamanagergroup='group0', datamanagertype='Adios2StMan' ),
         ))
  if COMPRESSOR=="None":
    Adminfo = makedminfo(
        Atabdesc,
        {
            'group0': {
                'OPERATORPARAMS': {
                    'COPY_ADIOS': {
                        'lossless_type' : LOSSLESS}
               } } } )      
  else:
    Adminfo = makedminfo(
        Atabdesc,
        {
            'group0': {
                'OPERATORPARAMS': {
                    'COPY_ADIOS': {
                        'Operator': COMPRESSOR,
                        'mode': MODE,
                        'Accuracy': str(ACCURACY),
                        'lossless_type' : LOSSLESS
                 }}}})

  group1=int(np.random.random()*1e4)
  group1=f'group{group1:04d}'
  print(f'Using {group1} for labels')
  Ttabdesc = maketabdesc(
        (makearrcoldesc('COPY_DATA', '',
            valuetype='complex', shape=cell_shape,
            datamanagergroup=group1, datamanagertype='TiledShapeStMan' ),
         ))
  Tdminfo = makedminfo(
        Ttabdesc,
        {
            group1: {
                'OPERATORPARAMS': {
                    'COPY_DATA': {}
               } } } )

  if 'COPY_ADIOS' in tb.colnames():
    if DELETEOLD:
      print('Remove old adios COPY')
      a_seq=tb.getdminfo("COPY_ADIOS")["SEQNR"]
      tb.removecols('COPY_ADIOS')
      print(f'Removing {FILENAME}/table.f{a_seq}.bp')
      shutil.rmtree(f'{FILENAME}/table.f{a_seq}.bp')
      tb.addcols(Atabdesc,dminfo=Adminfo)
    else:
      print('Reusing old adios COPY')
  else:
      tb.addcols(Atabdesc,dminfo=Adminfo)
      
  if 'COPY_DATA' in tb.colnames():
    if DELETEOLD:
      print('Remove old standard COPY_DATA')
      #t_seq=tb.getdminfo("COPY_DATA")["SEQNR"]
      tb.removecols('COPY_DATA')
      #print(f'Removing {FILENAME}/table.f{t_seq}_TSM1')
      #shutil.rmtree(f'{FILENAME}/table.f{t_seq}_TSM1')
      tb.addcols(Ttabdesc,dminfo=Tdminfo)
    else:
      print('Reusing old adios COPY')
  else:
      tb.addcols(Ttabdesc,dminfo=Tdminfo)

  if STEPS: # not equal zero
    steps=STEPS
    Nbase=int(SHAP[0]/steps)
    if steps<0:
        steps=len(np.unique(tb.getcol('TIME')))
        Nbase=int(SHAP[0]/steps)
        if (Nbase*steps!=SHAP[0]):
            steps = find_smallest_divisor(SHAP[0])    
            Nbase=SHAP[0]/steps
    print(f'Using {steps} steps to write and read new columns in steps of {Nbase}.')
  else:
    steps=1
    Nbase=SHAP[0]
    print(f'Using one step for writing and reading new columns.')
  tot_tic = time.time()
  for n in range(steps):
    print('Write %d/%d\t'%(n,steps))
    tic=time.time()
    vis=tb.getcol(DATACOL,nrow=Nbase,startrow=n*Nbase)
    fg=tb.getcol('FLAG',nrow=Nbase,startrow=n*Nbase)
    tsteps = time.time()-tic
    print(f'Read {Nbase} complex visibilities from {DATACOL} column in {tsteps:.3f}s')
    s=vis.shape
    if (COMPRESSOR == "mgard_complex")|(COMPRESSOR == "mgard"): # This perhaps should be true for all 
        vis=vis.reshape(-1)
        fg=vis.reshape(-1)
        Inan=np.where(np.isnan(vis)==True)[0] # Flag NaNs
        fg[Inan]=True
        Inan=np.where(fg==True)[0] 
        vis[Inan]=0              # Set flagged data to be zero
        vis=vis.reshape(s)
        fg=fg.reshape(s)
        # This failed when I tried to write the FLAG back with MGARD. Not sure why
        #tb.putcol('FLAG',fg,nrow=Nbase,startrow=n*Nbase)
    tic = time.time()
    tb.putcol('COPY_ADIOS',vis,nrow=Nbase,startrow=n*Nbase)
    tsteps = time.time()-tic
    print(f'Wrote {Nbase} compressed complex visibilities to ADIOS column in {tsteps:.3f}s')
  tb.close()
  tsteps = time.time()-tot_tic
  if (steps>1): print(f'Total Read/Write compressed complex visibilities from {DATACOL}/COPY_ADIOS column in {tsteps:.3f}s')

  tb=table(FILENAME,readonly=False)
  tot_tic = time.time()
  for n in range(steps):
    print('Read %d/%d\t'%(n,steps))
    #tic=time.time()
    #data=t.getcol('COPY_DATA',nrow=Nbase,startrow=n*Nbase)
    #tsteps = time.time()-tic
    #print(f'Read {Nbase} complex visibilities from COPY_DATA column in {tsteps:.3f}s')
    tic=time.time()
    vis=tb.getcol('COPY_ADIOS',nrow=Nbase,startrow=n*Nbase)
    tsteps = time.time()-tic
    print(f'Read {Nbase} compressed complex visibilities from COPY_ADIOS column in {tsteps:.3f}s')
    if np.mod(n,10)==0: # every 10th now
        data=tb.getcol(DATACOL,nrow=Nbase,startrow=n*Nbase)
        a1=tb.getcol('ANTENNA1',nrow=Nbase,startrow=n*Nbase)
        a2=tb.getcol('ANTENNA2',nrow=Nbase,startrow=n*Nbase)
        I=np.where(a1!=a2)[0]
        tic=np.nanstd(data[I])
        data-=vis
        print('Data Difference:',np.nanmax(np.abs(data[I])),np.nanstd(data[I]),'StdDev',tic)
    tic = time.time()
    tb.putcol('COPY_DATA',vis,nrow=Nbase,startrow=n*Nbase)
    tsteps = time.time()-tic
    print(f'Wrote {Nbase} complex visibilities to TILED column in {tsteps:.3f}s')
  a_seq=tb.getdminfo("COPY_ADIOS")["SEQNR"]
  t_seq=tb.getdminfo("COPY_DATA")["SEQNR"]
  tb.close()
  tsteps = time.time()-tot_tic
  if (steps>1): print(f'Total Read/Write compressed complex visibilities from COPY_ADIOS/COPY_DATA column in {tsteps:.3f}s')

  t_on_disk_size = get_size(f'{FILENAME}/table.f{t_seq}_TSM1')
  a_on_disk_size = get_size(f'{FILENAME}/table.f{a_seq}.bp')
  rat_on_disk_size=100.*a_on_disk_size/t_on_disk_size
  print(f'Native size: {t_on_disk_size} Compressed size: {a_on_disk_size} or {rat_on_disk_size:.1f}%')
  #print(f'ORIG write time: {tnocomp_complex:.3f}')
  #print(f'REAL[{COMPRESSOR1}] compression and write time: {tcomp_real:.3f}')
  #print(f'IMAG[{COMPRESSOR2}] compression and write time: {tcomp_imag:.3f}\n')
  #print('Total compression and write time: '
  #      f'{(tcomp_real+tcomp_imag):.3f} ({((tcomp_real+tcomp_imag)/tnocomp_complex):.1f}x)\n\n')
  #
  #print(f'ORIG read time: {(tread_complex):.3f} s')
  #print(f'REAL[{COMPRESSOR1}] decompression and read time: {(tdecomp_real):.3f} s')
  #print(f'REAL compression ratio: {size / r_on_disk_size:.2f}')
  #print(f'IMAG[{COMPRESSOR2}] decompression and read time: {(tdecomp_imag):.3f} s')
  #print(f'IMAG compression ratio: {size / i_on_disk_size:.2f}\n')
  #print('Total decompression and read time: '
  #      f'{(tdecomp_real+tdecomp_imag):.3f} s ({((tdecomp_real+tdecomp_imag)/tread_complex):.1f}x)\n\n')
  #if PLOT:
  #  plot(vis, visr, visi, cvis)
  #
  HISTORY=True
  if HISTORY==True:
    import time
    tb=table(f"{FILENAME}/HISTORY",readonly=False)
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
    d[n]=f'Applied compressor {COMPRESSOR} with accuracy {ACCURACY} to make COPY_ADIOS (and then COPY_DATA) from {DATACOL} with flagging'
    print('Writing HISTORY: ',d[n])
    tb.putcol('MESSAGE',d)
    d=tb.getcol('ORIGIN')
    d[n]=sys.argv[0]#+':'+k[-1]
    tb.putcol('ORIGIN',d)
    d=tb.getcol('ORIGIN')
    d[n]=sys.argv[0]#+':'+k[-1]
    tb.putcol('ORIGIN',d)
    tb.close()
  
if __name__ == "__main__":  
  parser = argparse.ArgumentParser(description=
                                   'Test the column-wise compression using the Adios2StMan storage manager in casacore tables')
  parser.add_argument("--compressor", type=str, default=COMPRESSOR, help="Global data compressor")
  parser.add_argument("--accuracy", type=str, default=ACCURACY, help="Global accuracy for data columns")
  parser.add_argument("--lossless", type=str, default=LOSSLESS, help="Final lossless data compressor")
  parser.add_argument("--filename", type=str, default=FILENAME, help="MS filename")
  parser.add_argument("--datacol", type=str, default=DATACOL, help="Data Column")
  parser.add_argument("--steps", type=int, default=0, help="Write a STEPS column in this number of steps.")
  parser.add_argument("--plot", action='store_true', help="(False) Plot comparison histograms.")
  parser.add_argument("--reuse", action='store_true', help="(False) delete and remake columns")

  DELETEOLD=True
  args = parser.parse_args()
  if args.accuracy != ACCURACY:
      ACCURACY = args.accuracy
  if args.steps:
    STEPS = args.steps #(STEPS==False) # Swap the setting
  if args.reuse:
    print('Swapping delete flag ',DELETEOLD)
    DELETEOLD = (args.reuse==False) # Swap the setting for delete
  if args.plot:
    PLOT = True
  if args.filename != FILENAME: 
    FILENAME = args.filename
  if args.datacol != DATACOL: 
    DATACOL = args.datacol
  if args.compressor not in COMPRESSORS:
      print(f"compressor argument needs to be one of {COMPRESSORS}")
      sys.exit()
  else:
      COMPRESSOR = args.compressor
  if args.lossless not in LOSS:
      print(f"lossless compressor argument needs to be one of {LOSS}")
      sys.exit()
  else:
      LOSSLESS = args.lossless
  #print(FILENAME,DATACOL,DELETEOLD,COMPRESSOR,ACCURACY)    

  if COMPRESSOR == "dysco":
    make_DYSCO_column(DATACOL=DATACOL,FILENAME=FILENAME,
        STEPS=STEPS,bitcount=ACCURACY, DELETEOLD=DELETEOLD)
  else:
    run(DATACOL=DATACOL,FILENAME=FILENAME,
        STEPS=STEPS,ACCURACY=ACCURACY,COMPRESSOR=COMPRESSOR,LOSSLESS=LOSSLESS,
      DELETEOLD=DELETEOLD)
  sys.exit()
  
