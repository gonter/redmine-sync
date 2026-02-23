#!/usr/bin/perl

# NOTE: that should be redesigned ...

use strict;

use Data::Dumper;
$Data::Dumper::Indent= 1;

use FileHandle;
use JSON;

use Redmine::CLI;

  binmode (STDOUT, ':utf8');
  binmode (STDERR, ':utf8');

  my $rm_cli= Redmine::CLI->new(cfg_stanza => $ENV{REDMINE});
  # print __LINE__, " rm_cli: ", Dumper ($rm_cli);

  $rm_cli->parse_args(@ARGV);
  # print __LINE__, " extra_options: ", Dumper($rm_cli->{extra_options});

  my ($cfg, $mRM)= $rm_cli->init();
  # print __LINE__, " rm_cli: ", Dumper ($rm_cli);

  my $res= $rm_cli->main_part2();
  print __LINE__, " rm_cli: res: ", Dumper($res);
  # print __LINE__, " rm_cli: ", Dumper ($rm_cli);
  print encode_json($res);

exit;

__END__

=head1 Requirements

=head2 WebService::Redmine

 * git clone git@github.com:igelhaus/perl-WebService-Redmine.git

=head1 TODOs

 * check due dates for an "alarm-tool"
 * show related issues, if possible with dependency graph

