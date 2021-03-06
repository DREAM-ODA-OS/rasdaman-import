#!/usr/bin/python
#
# Construct type information for a given image, printing the definition to a
# file, and printing the MDD/SET type names to std output.
#
# Usage: gettypes.py image_file dimensions coll_name output_file directory
#
#    image_file    path to the image for which rasdaman types should be generated
#    dimensions    type dimensionality
#    coll_name     collection name, used to construct the type names
#    directory     directory where files will be written
#
# Generates a type definition, e.g.:
#    struct coll_name_Pixel { short band1, band2, ...; };
#    typedef marray <coll_name_Pixel, 3> coll_name_Array;
#    typedef set<coll_name_Array> coll_name_Set;
#
# Prints the type names to standard output, e.g:
#    coll_name_Array coll_name_Set
# 
# Files and information written by this script:
# - Type definition is written to coll_name.dl
# - CRS information is written to coll_name.crs
# - Pixel bbox      is written to coll_name.pbbox
# - Geo bbox        is written to coll_name.gbbox
# - Metadata        is written to coll_name.metadata
#
# Author        Dimitar Misev
# ----------------------------------------------------------------------------


from osgeo import gdal
from osgeo.gdalconst import *
import os
import sys

PIXEL = "Pixel"
ARRAY = "Array"
SET = "Set"

if len(sys.argv) != 5:
  print "Usage: gettypes.py image_file dims coll_name directory"
  print ""
  print "  image_file    path to the image for which rasdaman types should be generated"
  print "  dims          type dimensionality"
  print "  coll_name     collection name, used to construct the type names"
  print "  directory     directory where files will be written"
  sys.exit(1)

f = sys.argv[1]
d = sys.argv[2]
coll = sys.argv[3]
outdir = sys.argv[4]

outfPrefix = outdir + "/" + coll
dims = int(d)

# gdal
inDs = gdal.Open(f, GA_ReadOnly)

pixelType = ""
pixelTypeName = ""
arrayType = ""
arrayTypeName = ""
setType = ""
setTypeName = ""

# Translate GDAL type to rasdaman base type
# 
# GDAL types: enum GDALDataType
#    GDT_Unknown 	
#    Unknown or unspecified type
#
#    GDT_Byte 	
#    Eight bit unsigned integer
#
#    GDT_UInt16 	
#    Sixteen bit unsigned integer
#
#    GDT_Int16 	
#    Sixteen bit signed integer
#
#    GDT_UInt32 	
#    Thirty two bit unsigned integer
#
#    GDT_Int32 	
#    Thirty two bit signed integer
#
#    GDT_Float32 	
#    Thirty two bit floating point
#
#    GDT_Float64 	
#    Sixty four bit floating point
#
#    GDT_CInt16 	
#    Complex Int16
#
#    GDT_CInt32 	
#    Complex Int32
#
#    GDT_CFloat32 	
#    Complex Float32
#
#    GDT_CFloat64 	
#    Complex Float64 

nBands = inDs.RasterCount
rasType = ""
initval = ""
typeids = ["","c","us","s","ul","l",".0",".0"]

for i in range(1, nBands + 1):
  gdalType = inDs.GetRasterBand(i).DataType
  if pixelType != "":
    pixelType += ","
    initval += ",0" + typeids[gdalType]
  else:
    if gdalType == 1:
      pixelType += "char"
      if inDs.RasterCount == 1:
        rasType = "Grey"
      elif inDs.RasterCount == 3 and pixelType == "char band1,char band2,char":
        rasType = "RGB"
      initval += "0c"
    elif gdalType == 2:
      pixelType += "unsigned short"
      rasType = "UShort"
      initval += "0us"
    elif gdalType == 3:
      pixelType += "short"
      rasType = "Short"
      initval += "0s"
    elif gdalType == 4:
      pixelType += "unsigned long"
      rasType = "ULong"
      initval += "0ul"
    elif gdalType == 5:
      pixelType += "long"
      rasType = "Long"
      initval += "0l"
    elif gdalType == 6:
      pixelType += "float"
      rasType = "Float"
      initval += "0.0"
    elif gdalType == 7:
      pixelType += "double"
      rasType = "Double"
      initval += "0.0"
    else:
      print "can't handle GDAL type: " + gdalType
      sys.exit(1)
  if nBands > 1:
    pixelType += " band" + str(i)

if nBands > 1:
  initval = "{" + initval + "}"
#
# output initializing value
#
f = open(outfPrefix + ".init",'w')
print >>f, initval
f.close()

f = open(outfPrefix + ".dl",'w')

# determine pixel, array and set type names
if inDs.RasterCount == 1 or rasType == "RGB":
  pixelTypeName = pixelType
  if rasType == "RGB":
    pixelTypeName = "RGBPixel"
  if dims == 1:
    arrayTypeName = rasType + "String"
    setTypeName = rasType + "Set1"
  elif dims == 2:
    arrayTypeName = rasType + "Image"
    setTypeName = rasType + "Set"
  elif dims == 3:
    arrayTypeName = rasType + "Cube"
    setTypeName = rasType + "Set3"
else:
  pixelTypeName = coll + "_" + PIXEL
  arrayTypeName = coll + "_" + ARRAY
  setTypeName = coll + "_" + SET
  print >>f, "struct " + pixelTypeName + " { " + pixelType + "; };"
  
print >>f, "typedef marray <" + pixelTypeName + ", " + d + "> " + arrayTypeName + ";"
print >>f, "typedef set <" + arrayTypeName + "> " + setTypeName + ";"
f.close()

print arrayTypeName + " " + setTypeName

#
# output pixel bounding box
#
f = open(outfPrefix + ".pbbox",'w')
print >>f, inDs.RasterXSize
print >>f, inDs.RasterYSize
f.close()

#
# output geo bounding box
#
f = open(outfPrefix + ".bbbox",'w')
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
print >>f, '%.17f' % xmin
print >>f, '%.17f' % ymin
print >>f, '%.17f' % xmax
print >>f, '%.17f' % ymax
f.close()

#
# output crs
#
f = open(outfPrefix + ".crs",'w')
print >>f, inDs.GetProjection()
f.close()

#
# output metadata
#
f = open(outfPrefix + ".metadata",'w')
print >>f, inDs.GetMetadata()
f.close()
