def Compare(A,B):
    import numpy as np
    import sys
    from casacore.tables import ( table  )
    from casacore.images import (  image  )

    print('Opening Reference ',A)
    im1=image(A)
    d_ref=im1.getdata()
    print('Opening New ',B)
    im2=image(B)
    d_new=im2.getdata()
    d_rms=np.std(d_ref)
    d_diff=np.std(d_ref-d_new)
    d_max=np.max(np.abs(d_ref-d_new))
    print('#ImageErrors: Image_RMS, Image_Max/Ref_Max, DeltaImage_RMS, DeltaImage_Max, dImRMS/RMS, dImMAX/RMS')
    print('Image Errors ',d_rms,np.max(d_new)/np.max(d_ref),d_diff,d_max,d_diff/d_rms,d_max/d_rms)
    return(d_diff/d_rms) # return the fractional \Delta RMS over RMS


import sys
if (len(sys.argv)>2):
    A=sys.argv[-2]
    B=sys.argv[-1]
    print(Compare(A,B))
else:
    print('Usage: Reference-Image Compressed-Image')
