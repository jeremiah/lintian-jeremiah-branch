#!/usr/bin/perl
#
# Test POD formatting.  Taken essentially verbatim from the examples in the
# Test::Pod documentation.

use strict;
use Test::More;
eval 'use Test::Pod 1.00';
plan skip_all => "Test::Pod 1.00 required for testing POD" if $@;
all_pod_files_ok(all_pod_files("$ENV{LINTIAN_ROOT}/lib"));
