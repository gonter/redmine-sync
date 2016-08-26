#!/usr/bin/perl

# NOTE: that should be redesigned ...

use strict;

use Data::Dumper;
$Data::Dumper::Indent= 1;

use Redmine::CLI;

  my $rm_cli= new Redmine::CLI();
  # print __LINE__, " rm_cli: ", Dumper ($rm_cli);

  $rm_cli->parse_args(@ARGV);

  my ($cfg, $mRM)= $rm_cli->init();
  # print __LINE__, " rm_cli: ", Dumper ($rm_cli);

  $rm_cli->main_part2();

exit;
