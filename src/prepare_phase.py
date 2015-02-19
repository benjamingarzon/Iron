#!/usr/bin/python 
from nipy import load_image, save_image
from nipy.core.api import Image
import numpy as np
import sys

THR = 4096

def prepare_phase(dataFile, prepFile):
    dataImg = load_image(dataFile)
    data = dataImg.get_data()
    nFrames = data.shape[3]

# fix voxels outside range
    data[data > THR] = THR
    data[data < -THR] = -THR

# scale data
    dataPrep = np.pi*data/THR
    print np.max(data)
    # save image
    dataImg = Image(dataPrep, dataImg.coordmap)
    newimg = save_image(dataImg, prepFile)

def main():
    dataFile = sys.argv[1]
    prepFile = sys.argv[2]

    prepare_phase(dataFile, prepFile)


if __name__ == "__main__":
    main()

