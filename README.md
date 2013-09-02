Rasdaman import scripts
=======================

This is a collection of Bash scripts to help inserting and dropping data in
*rasdaman* (http://rasdaman.org/)


Configuration
-------------

Copy *conf/import.var.template* to *conf/import.var* and adapt the empty variables.


Usage
-----

Import scripts are placed in separate directories under *import/*. To create new
import, it is best to copy an existing directory and adapt for the new data.
The import scripts are generally organized as follows:

 * *import.cfg* - contains configuration specific for the import
 * *import.sh*  - deals with importing the data into rasdaman/petascope
 * *drop.sh*    - used to drop the imported data

This is just a guideline of course. The import.sh scripts are typically 
organized with three functions:

 * *initcolls*  - create a collection and initialize the MDD object (to prepare 
                for partial updates for example)
 * *importras*  - import data into rasdaman
 * *importpet*  - import coverage metadata into petascope
 
Import scripts depend heavily on common functionality implemented in util/
