CFLAGS=-Wall
LIBS=-framework AppKit -framework Virtualization -fobjc-arc -fobjc-link-runtime
CC=clang

macosvm: VMInstance.o main.o macosvm.entitlements
	$(CC) -o $@ VMInstance.o main.o $(LDFLAGS) $(LIBS)
	codesign --force --sign - -o runtime --entitlements macosvm.entitlements --timestamp\=none --generate-entitlement-der $@

VMInstance.o: VMInstance.h VMInstance.m
	$(CC) $(CPPFLAGS) $(CFLAGS) -c VMInstance.m

main.o: VMInstance.h main.m
	$(CC) $(CPPFLAGS) $(CFLAGS) -c main.m

clean:
	rm -f VMInstance.o main.o macosvm
