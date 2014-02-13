#!/bin/bash

for i in $(seq 1 8); do
  rasql -q "select encode((c.2 * {1c,0c,0c} + c.1 * {0c,1c,0c} + c.0 * {0c,0c,1c})[*:*,*:*,$i], \"GTiff\", \"xmin=660000;xmax=680000;ymin=5570000;ymax=5590000;crs=EPSG:32633;nodata=0\") from gisat AS c" --out file
  mv rasql_1.* gisat$i.tif
  rasql -q "select encode(c.3[*:*,*:*,$i], \"GTiff\", \"xmin=660000;xmax=680000;ymin=5570000;ymax=5590000;crs=EPSG:32633;nodata=0\") from gisat AS c" --out file
  mv rasql_1.* gisat_nir$i.tif
  rasql -q "select encode(c.4[*:*,*:*,$i], \"GTiff\", \"xmin=660000;xmax=680000;ymin=5570000;ymax=5590000;crs=EPSG:32633;nodata=0\") from gisat AS c" --out file
  mv rasql_1.* gisat_swir$i.tif
done
