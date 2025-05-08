SRC_FILES := $(wildcard *.c)
OBJ_FILES := $(SRC_FILES:.c=.o)
ARCHIVE := complex.a

.PHONY: all clean

%.o: %.c
	clang -c -o $@ $<

$(ARCHIVE): $(OBJ_FILES)
	llvm-ar rc $@ $^

all: $(ARCHIVE)

clean:
	$(RM) $(ARCHIVE) $(OBJ_FILES)
