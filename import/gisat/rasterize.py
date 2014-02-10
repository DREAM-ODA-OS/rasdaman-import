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


parser = optparse.OptionParser("usage: %prog [options] arg1 arg2")
parser.add_option("-f", "--file", dest="mask",
                  type="string",
                  help="specify cloud mask shapefile to rasterize")
parser.add_option("-o", "--output", dest="raster", default="raster.tif",
                  type="string", help="output file to which to write the rasterized mask, default raster.tif")
parser.add_option("-p", "--pixelsize", dest="pixel_size", default=20,
                  type="int", help="pixel size of the output raster mask, default 20")
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
raster_fn = options.raster
pixel_size = options.pixel_size
attribute_filter = options.attribute_filter
burn_value = options.burn_val
nodata_value = options.nodata

print("rasterizing " + vector_fn + " shapefile to " + raster_fn + " raster")
print("pixel size: " + str(pixel_size) + ", burn value: " + str(burn_value))
print("attribute filter: " + attribute_filter + ", nodata: " + str(nodata_value))

# Open the data source and read in the extent
source_ds = ogr.Open(vector_fn)
source_layer = source_ds.GetLayer()
source_layer.SetAttributeFilter(attribute_filter)
source_srs = source_layer.GetSpatialRef()
x_min, x_max, y_min, y_max = source_layer.GetExtent()

# Create the destination data source
x_res = int((x_max - x_min) / pixel_size)
y_res = int((y_max - y_min) / pixel_size)
target_ds = gdal.GetDriverByName('GTiff').Create(raster_fn, x_res, y_res, gdal.GDT_Byte)
target_ds.SetGeoTransform((x_min, pixel_size, 0, y_max, 0, -pixel_size))
band = target_ds.GetRasterBand(1)
band.SetNoDataValue(nodata_value)

# Rasterize
gdal.RasterizeLayer(target_ds, [1], source_layer, burn_values=[burn_value])

print "done, output written to " + raster_fn
