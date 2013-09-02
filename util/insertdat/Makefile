include ../../conf/import.var
include ../../conf/import.dev

compile: insertdat

clean: 
	-rm -f *.o
	-rm -f insertdat

insertdat: insertdat.o
	g++ -o insertdat insertdat.o $(LIBS) -g 

insertdat.o: insertdat.cpp
	g++ $(DEFS) $(INCS) -g -c insertdat.cpp
