include ../../conf/import.var
include ../../conf/import.dev

compile: insertbin

clean: 
	-rm -f *.o
	-rm -f insertbin

insertbin: insertbin.o
	g++ -o insertbin insertbin.o $(LIBS) -g 

insertbin.o: insertbin.cpp
	g++ $(DEFS) $(INCS) -g -c insertbin.cpp
