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

__END__

=head1 Requirements

=head2 WebService::Redmine

 * git clone git@github.com:igelhaus/perl-WebService-Redmine.git

=head1 TODOs

 * check due dates for an "alarm-tool"
 * show related issues, if possible with dependency graph

