#!/usr/bin/python
#
# Rasterize an input OGR shapefile to a GTiff raster file.
#
# Dimitar Misev
# 2014-feb-10

import random
import optparse
import sys
from osgeo import gdal, ogr
from osgeo.gdalconst import *


parser = optparse.OptionParser("usage: %prog [options] arg1 arg2")
parser.add_option("-f", "--file", dest="mask",
                  type="string",
                  help="specify cloud mask shapefile to rasterize")
parser.add_option("-r", "--raster", dest="original",
                  type="string",
                  help="specify original file to which the cloud mask applies")
parser.add_option("-o", "--output", dest="raster", default="raster.tif",
                  type="string", help="output file to which to write the rasterized mask, default raster.tif")
parser.add_option("-a", "--attribute", dest="attribute_filter", default="DN = 0",
                  type="string", help="specify an attribute filter, default 'DN = 0'")
parser.add_option("-b", "--burnval", dest="burn_val", default=1,
                  type="int", help="specify a value to be burned, default 1")
parser.add_option("-n", "--nodata", dest="nodata", default=0,
                  type="int", help="specify a nodata value of the output raster, default 0")

(options, args) = parser.parse_args()
    
vector_fn = options.mask
if vector_fn is None:
  parser.error("Please specify an input shapefile.")
  sys.exit(1)
original_fn = options.original
if original_fn is None:
  parser.error("Please specify an original input file.")
  sys.exit(1)
raster_fn = options.raster
attribute_filter = options.attribute_filter
burn_value = options.burn_val
nodata_value = options.nodata

print("rasterizing " + vector_fn + " shapefile to " + raster_fn + " raster")
print("burn value: " + str(burn_value))
print("attribute filter: " + attribute_filter + ", nodata: " + str(nodata_value))

# Open the data source and read in the extent
source_ds = ogr.Open(vector_fn)
source_layer = source_ds.GetLayer()
source_layer.SetAttributeFilter(attribute_filter)
source_srs = source_layer.GetSpatialRef()

inDs = gdal.Open(original_fn, GA_ReadOnly)
geotransform = inDs.GetGeoTransform()
xmin = geotransform[0]
ymin = geotransform[3]
xmax = (geotransform[1] * inDs.RasterXSize + geotransform[0])
ymax = (geotransform[5] * inDs.RasterYSize + geotransform[3])
if xmin > xmax:
  tmp = xmin
  xmin = xmax
  xmax = tmp
if ymin > ymax:
  tmp = ymin
  ymin = ymax
  ymax = tmp
pixel_size_x = int((xmax - xmin) / inDs.RasterXSize)
pixel_size_y = int((xmax - xmin) / inDs.RasterXSize)

# Create the destination data source
target_ds = gdal.GetDriverByName('GTiff').Create(raster_fn, inDs.RasterXSize, inDs.RasterYSize, gdal.GDT_Byte)
target_ds.SetGeoTransform((xmin, pixel_size_x, 0, ymax, 0, -pixel_size_y))
band = target_ds.GetRasterBand(1)
band.SetNoDataValue(nodata_value)

# Rasterize
gdal.RasterizeLayer(target_ds, [1], source_layer, burn_values=[burn_value])

print "done, output written to " + raster_fn
