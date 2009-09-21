#!/usr/bin/perl -w

use Test::More qw(no_plan);

BEGIN { use_ok('Lintian::PDepMap'); }

my $map;

ok(eval { $map = Lintian::PDepMap->new(); }, 'Create');

my %prop = (name => 'John Doe', age => 20);

ok($map->add('P1', \%prop), "Add node with properties as a hash");

is_deeply($map->getProp('P1'), \%prop, "Properties are preserved");

ok($map->add('P2', 'P1'), "Nodes can be added without properties");

ok(eval {$map->satisfy('P1');}, "Nodes can be satisfied");

ok($map->addp('foo', 'P', '1', '2', {name => 'test'}), "Nodes can be added with prefix");
