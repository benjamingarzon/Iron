#!/usr/bin/python 
from nipy import load_image, save_image
from nipy.core.api import Image
import numpy as np
import sys

def dephase_slices(dataFile, dephFile):
    dataImg = load_image(dataFile)
    data = dataImg.get_data()

    if len(data.shape) < 4:
        data[:, :, 1::2] = -data[:, :, 1::2]
    else:
        data[:, :, 1::2, :] = -data[:, :, 1::2, :]
        
    data[ np.abs(data == 0) ] = 0    
# save images
    dephImg = Image(data, dataImg.coordmap)
    newimg = save_image(dephImg, dephFile)

def main():
    dataFile = sys.argv[1]
    dephFile = sys.argv[2]
    dephase_slices(dataFile, dephFile)

if __name__ == "__main__":
    main()
