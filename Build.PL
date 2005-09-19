#!/usr/bin/perl
use strict;
use warnings;
use Module::Build;
my $build = Module::Build->new(
  module_name => 'Class::DBI::utf8',
  license     => 'perl',
  requires    => {
    'perl' => 5.008,
    'Class::DBI' => '0.94',
  },
  build_requires => {
    'DBD::SQLite'  => 0,
    'Test::More'   => 0,
  },
  create_makefile_pl => 'traditional',
  create_readme => 1,
)->create_build_script();
