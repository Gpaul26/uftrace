VERSION := 0.17

# Default settings
prefix ?= /usr/local
bindir = $(prefix)/bin
libdir = $(prefix)/lib/uftrace
etcdir = $(prefix)/etc
mandir = $(prefix)/share/man
docdir = $(srcdir)/doc
completiondir = $(etcdir)/bash_completion.d
srcdir = $(CURDIR)
objdir ?= $(O:$(O=)=$(CURDIR))

# Architecture detection
uname_M := $(shell uname -m 2>/dev/null || echo not)
ARCH ?= $(shell echo $(uname_M) | sed -e s/i.86/i386/ -e s/arm.*/arm/)
ifneq ($(findstring x86,$(ARCH)),)
  ifneq ($(findstring m32,$(CC) $(CFLAGS)),)
    override ARCH := i386
  endif
endif

# Allow overriding CC, AR, LD with CROSS_COMPILE prefix
define allow-override
  $(if $(or $(findstring environment,$(origin $(1))),\
            $(findstring command line,$(origin $(1)))),,\
    $(eval $(1) = $(2)))
endef
$(call allow-override,CC,$(CROSS_COMPILE)gcc)
$(call allow-override,AR,$(CROSS_COMPILE)ar)
$(call allow-override,LD,$(CROSS_COMPILE)ld)

# Common flags
COMMON_CFLAGS := -std=gnu11 -D_GNU_SOURCE -iquote $(srcdir) -iquote $(objdir) -iquote $(srcdir)/arch/$(ARCH)
COMMON_CFLAGS += -W -Wall -Wno-unused-parameter -Wno-missing-field-initializers -Wdeclaration-after-statement -Wstrict-prototypes
COMMON_LDFLAGS := -ldl -pthread -Wl,-z,noexecstack
COMMON_LDFLAGS += $(if $(ANDROID),-landroid,-lrt)

# Conditional flags
ifneq ($(elfdir),)
  COMMON_CFLAGS += -I$(elfdir)/include
  COMMON_LDFLAGS += -L$(elfdir)/lib
endif
ifeq ($(DEBUG),1)
  COMMON_CFLAGS += -O0 -g3 -DDEBUG_MODE=1 -Werror
else
  COMMON_CFLAGS += -O2 -g -DDEBUG_MODE=0
endif
ifeq ($(TRACE),1)
  TRACE_CFLAGS := -pg -fno-omit-frame-pointer
endif
ifeq ($(COVERAGE),1)
  COVERAGE_CFLAGS := -O0 -g --coverage -U_FORTIFY_SOURCE
  COMMON_CFLAGS += $(COVERAGE_CFLAGS)
  COMMON_LDFLAGS += --coverage
endif
ifneq ($(SAN),)
  SAN_CFLAGS := -O0 -g -fsanitize=$(if $(filter all,$(SAN)),$(DEFAULT_SANITIZERS),$(SAN))
  COMMON_CFLAGS += $(SAN_CFLAGS)
endif

# Component-specific flags
UFTRACE_CFLAGS := $(COMMON_CFLAGS) $(TRACE_CFLAGS)
LIB_CFLAGS := $(COMMON_CFLAGS) -fPIC -fvisibility=hidden -fno-omit-frame-pointer -fno-builtin -fno-tree-vectorize -DLIBMCOUNT
TEST_CFLAGS := $(COMMON_CFLAGS) -DUNIT_TEST
PYTHON_CFLAGS := $(COMMON_CFLAGS) -fPIC

UFTRACE_LDFLAGS := $(COMMON_LDFLAGS) -lm
LIB_LDFLAGS := $(COMMON_LDFLAGS) -Wl,--no-undefined
TEST_LDFLAGS := $(COMMON_LDFLAGS) -lm

# Targets
TARGETS := uftrace python/uftrace_python.so $(LIBMCOUNT_TARGETS) libmcount/libmcount-nop.so misc/demangler misc/symbols misc/dbginfo
TARGETS := $(patsubst %,$(objdir)/%,$(TARGETS))
LIBMCOUNT_TARGETS := libmcount/libmcount.so libmcount/libmcount-fast.so libmcount/libmcount-single.so libmcount/libmcount-fast-single.so

# Source and object files
UFTRACE_SRCS := $(wildcard $(srcdir)/uftrace.c $(srcdir)/cmds/*.c $(srcdir)/utils/*.c)
UFTRACE_OBJS := $(patsubst $(srcdir)/%.c,$(objdir)/%.o,$(UFTRACE_SRCS))

LIBMCOUNT_SRCS := $(filter-out %-nop.c,$(wildcard $(srcdir)/libmcount/*.c))
LIBMCOUNT_OBJS := $(patsubst $(srcdir)/%.c,$(objdir)/%.op,$(LIBMCOUNT_SRCS))

# Rules
all: $(objdir)/.config $(TARGETS)

$(objdir)/.config:
    $(error Please run 'configure' first)

$(objdir)/%.o: $(srcdir)/%.c $(COMMON_DEPS)
    $(QUIET_CC)$(CC) $(UFTRACE_CFLAGS) -c -o $@ $<

$(objdir)/%.op: $(srcdir)/%.c $(LIBMCOUNT_DEPS)
    $(QUIET_CC_FPIC)$(CC) $(LIB_CFLAGS) -c -o $@ $<

$(objdir)/libmcount/libmcount.so: $(LIBMCOUNT_OBJS) $(LIBMCOUNT_UTILS_OBJS) $(LIBMCOUNT_ARCH_OBJS)
    $(QUIET_LINK)$(CC) -shared -o $@ $^ $(LIB_LDFLAGS)

# Install
install: all
    $(INSTALL) -d -m 755 $(DESTDIR)$(bindir) $(DESTDIR)$(libdir) $(DESTDIR)$(completiondir)
    $(INSTALL) $(objdir)/uftrace $(DESTDIR)$(bindir)/uftrace
    $(INSTALL) $(objdir)/libmcount/*.so $(DESTDIR)$(libdir)/

clean:
    $(RM) $(objdir)/*.{o,op,oy,so,a} $(objdir)/cmds/*.o $(objdir)/utils/*.{o,op,oy} $(objdir)/misc/*.o $(TARGETS)

.PHONY: all config install clean
