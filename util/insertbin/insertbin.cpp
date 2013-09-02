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

r_Float init(const r_Point&pt) {
  return t[n-pt[1]-1][pt[0]];
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

  try {
    f = fopen(argv[7],"r");
    fread(&m, sizeof(int), 1, f);
    fread(&n, sizeof(int), 1, f);
    t = new float*[n];
    for (i=0; i<n; ++i) t[i] = new float[m];
    fseek(f, 0 , SEEK_END);
    int size = ftell(f);
    k = size / (n*m*sizeof(float)+2*sizeof(int));
    fseek(f, 0 , SEEK_SET);

    transaction.begin();
    r_Minterval domain;
    r_Ref< r_Marray<r_Float> >  image;   
    r_Ref< r_Set<r_Ref< r_Marray<r_Float> > > > collection;

    unsigned int typeSize = 4;
    r_Minterval tiling;
    tiling = r_Minterval(3) << r_Sinterval(0, 71) << r_Sinterval(0, 360) << r_Sinterval(0, 60);
    
    r_Aligned_Tiling *tilingObj = new r_Aligned_Tiling(tiling, typeSize * tiling.cell_count());
    r_Storage_Layout *mystl = new r_Storage_Layout(tilingObj);

    
    collection = new (&database, "FloatSet3") r_Set< r_Ref< r_Marray<r_Float> > >;
    database.set_object_name(*collection, argv[6]);
    domain = r_Minterval(3) << r_Sinterval(0, m - 1) << r_Sinterval(0, n-1) << r_Sinterval(0, k-1);
    image = new (&database, "FloatCube") r_Marray<r_Float> (domain);
    image->set_storage_layout(mystl);
    collection->insert_element(image);
    transaction.commit();

    
    transaction.begin();
    
    int read;
    char query[50];
    sprintf(query, "UPDATE %s AS cube SET cube ASSIGN $1 ", argv[6]);
    for (int ik = 0; ik < k-1; ++ik) {
      printf("inserting %d / %d\n", ik, k);
      fseek(f, 8, SEEK_CUR); // bypassing the size      
      domain[2].set_interval(ik, ik);
      for (i=0; i<n; ++i) read = fread(t[i], sizeof(float), m, f);
      image = new (&database, "FloatCube") r_Marray<r_Float> (domain, init);
      r_OQL_Query *oquery = new r_OQL_Query(query);
      (*oquery) << *image;
      r_oql_execute(*oquery);	
      transaction.commit();
      transaction.begin();
      delete oquery;
    }
    fclose(f);
  

  } catch (r_Error& err) {
    cout << err.what() << endl;
  }
    
  database.close();
  return 0;
}
