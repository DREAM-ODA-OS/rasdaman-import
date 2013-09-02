#include "config.h"

#ifdef EARLY_TEMPLATE
#define __EXECUTABLE__
#ifdef __GNUG__
#include "raslib/template_inst.hh"
#endif
#endif

using namespace std;

#include <iostream>
#include <fstream>
#include <iomanip>
#include <sstream>
#include <stdlib.h>
#include <getopt.h>
#include <list>

#include "raslib/rminit.hh"
#include "rasodmg/marray.hh"
#include "rasodmg/ref.hh"
#include "rasodmg/set.hh"
#include "rasodmg/database.hh"
#include "rasodmg/partinsert.hh"
#include "raslib/type.hh"
#include "raslib/odmgtypes.hh"
#include "raslib/error.hh"


using namespace std;

#define DEBUG_MAIN
#include "rasdaman.hh"
#include "debug.hh"

FILE *f;
float **t;

int n, m, k;
float data[10000];

r_Float init(const r_Point&pt) {
  return data[pt[0]];
}

int main(int argc, char **argv) {

  int i;
  r_Database database;
  r_Transaction transaction;

  if (argc != 8) {
    printf("Syntax %s server port user password database collection_name file_name\n", argv[0]);
    return 0;
  }

  int port = atoi(argv[2]);

  database.set_servername(argv[1], port);
  database.set_useridentification(argv[3], argv[4]);
  database.open(argv[5]);


  int nd = 0;
  int x;

  try {
    f = fopen(argv[7],"r");
    while (!feof(f) ) {
      fscanf(f, "%d ", &x);
      data[nd++]=x;
    }

    transaction.begin();
    r_Minterval domain;
    r_Ref< r_Marray<r_Float> >  image;   
    r_Ref< r_Set<r_Ref< r_Marray<r_Float> > > > collection;
    
    collection = new (&database, "FloatSet1") r_Set< r_Ref< r_Marray<r_Float> > >;
    database.set_object_name(*collection, argv[6]);
    domain = r_Minterval(1) << r_Sinterval(0, nd-1);
    image = new (&database, "FloatString") r_Marray<r_Float> (domain, init);
    collection->insert_element(image);
    transaction.commit();
    fclose(f);

  } catch (r_Error& err) {    
    printf("Error: ");
    cout << err.what() << endl;
  }
    
  database.close();
  return 0;
}
