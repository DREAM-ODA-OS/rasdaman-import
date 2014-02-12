Summary
=======
Scripts that fitting rasdaman into the ODA-OS ingestion work-flow in DREAM.

Usage
=====
The *import.sh* script allows ingestion into rasdaman, *drop.sh* deletes all the
data ingested (to be extended with arguments for more fine-grained deletion).
```
Usage: import.sh [OPTION]...

Description: import DREAM data.

Options:
  -f, --file FILE
    specify file to import, can be an archive or TIFF file.
  -m, --metadata FILE
    specify EO-O&M metadata file.
  -c, --coverage COVERAGE_NAME
    specify coverage name.
  -h, --help
    display this help and exit
```
All three parameters, -f, -m, and -c are mandatory.

Data model in rasdaman
======================
In rasdaman the data for each coverage is modelled as a 3D x/y/t cube.
 * x/y are computed from the coordinates/resolution directly from the input file
 * t is computed from the timestamp in the EO-O&M metadata file
Since a coverage corresponds to a single 3D x/y/t cube, all time slices should
be imported to the same *-c coverage_name*

Restriction
===========
For the data to be imported correctly at the moment, the files belonging to one
coverage must be imported in order of time. The import will still work if they
are unordered, but the data imported will not be tied to the correct time index
in rasdaman.

This is due to the fact that inserting slices in the middle of an existing
coverage is very costly in rasdaman. More information can be found in this
ticket: http://rasdaman.org/ticket/617

Once the ticket has been resolved, the import script will be updated to work
without this restriction.
