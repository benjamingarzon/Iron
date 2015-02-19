#!/usr/bin/python 

# -*- coding: utf8
# Author: Benjamin Garzon <benjamin.garzon@gmail.com>,
# License: BSD 3 clause

import sys
from nipy import load_image, save_image
from nipy.core.api import Image
import random
import numpy as np
import warnings

warnings.simplefilter(action = "ignore", category = FutureWarning)

def saveIm(x, coordmap, fname):
    auxImg = Image(x.astype(np.float32), coordmap)
    newimg = save_image(auxImg, fname)

def inImage(x, shape):
# check that x is within the image
    if x[0]>0 and x[1]>0 and x[2]>0 and x[0]<shape[0] \
        and x[1]<shape[1] and x[2]<shape[2]:
        return True
    else: 
        return False
 
def getNeighbours(x, shape):
    r = [-1, 0, 1]
    return [(x[0]+i,x[1]+j,x[2]+k) for i in r for j in r for k in r 
        if (i,j,k)!=(0,0,0) and inImage((x[0]+i,x[1]+j,x[2]+k), shape) 
            and abs(i)+abs(j)+abs(k) < 2]

def grow_roi(roi_file, mask_file, target_voxels, grown_roi_file):

    roiImg = load_image(roi_file)
    roi = roiImg.get_data()>0

    maskImg = load_image(mask_file)
    mask = maskImg.get_data()>0

    shape = roi.shape

    coords = np.where(roi)
    points = set(zip(coords[0], coords[1], coords[2]))

    
    # Go through voxels and calculate number of neighbours to identify boundary
    
    if np.sum(roi) >= target_voxels:
        print("ROI has already more that %d voxels"% target_voxels)
        
    while(np.sum(roi) < target_voxels):
    
        boundary = set()
        for point in points:
            for x in getNeighbours(point, shape):
                if mask[x[0], x[1], x[2]] and not roi[x[0], x[1], x[2]]:
                    boundary.add(x)
                    
        points = boundary

        if len(boundary)==0:
            print(
                "Number of voxels (%d) allowed by the mask already reached."
                %np.sum(roi))
            break
                
        for point in sorted(boundary, key = lambda x: random.random()) :

            roi[point[0], point[1], point[2]] = True
            if np.sum(roi) >= target_voxels:
                break

    saveIm(roi, roiImg.coordmap, grown_roi_file)

def main():

    roi_file = sys.argv[1]
    mask_file = sys.argv[2]
    target_voxels = sys.argv[3]
    grown_roi_file = sys.argv[4]

    grow_roi(roi_file, mask_file, int(target_voxels), grown_roi_file)

if __name__ == "__main__":
    main()

