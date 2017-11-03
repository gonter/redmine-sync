
=head3 Environment variables

  REDMINE ... specify stanza of selected Redmine instance

=pod

=head1 NAME

  Redmine::CLI

=head1 DESCRIPTION

  experimental stuff for something like a Redmine command line interface

=cut

package Redmine::CLI;

use strict;

use Data::Dumper;
use Pod::Simple::Text;
use FileHandle;

autoflush STDOUT 1;

use Util::JSON;
use Util::Simple_CSV;
use Util::Matrix;

use Redmine::Wrapper;

=head1 HELP TOPICS

=cut

my %HELP=
(
  'topics' => <<EOPOD,
=head2 TOPICS

The following help topics are available

=over 1

=item overview

=item environment

=back

=cut
EOPOD
  'overview' => <<EOPOD,
=head2 Overview

  help [topic] (this overview)
  list
  show ticket
=cut
EOPOD

  'env' => <<EOPOD,
=head2 Enivironment

=head3 Environment variables

  REDMINE ... specify stanza of selected Redmine instance

=head3 default attributes

  project_name
  ticket_number
  out_csv

=cut
EOPOD
);

my $default_config_fnm= 'redmine.json';
my @default_home_dirs= ('etc', undef, 'bin');

my @env_vars= qw(project_name tracker_name ticket_number out_csv subject);
my %env_vars= map { $_ => 1 } @env_vars;

sub new
{
  my $class= shift;

  my $obj=
  {
     # defaults
     'cfg_stanza'   => 'Redmine',
     'op_mode'      => undef,
     # 'project_name' => undef,
     'tracker_name' => 'Task',
  };

  my @cfg_fnm= (
      $ENV{REDMINE_CONFIG},
      $default_config_fnm,
      map { join ('/', $ENV{'HOME'}, $_, $default_config_fnm) } @default_home_dirs
  );

  while (@cfg_fnm)
  {
    my $f= shift (@cfg_fnm);
    next unless (defined ($f));
    # print "NOTE: trying [$f] as config filen name\n";
    if (-f $f)
    {
      print "NOTE: picked [$f] as config filen name\n";
      $obj->{'cfg_fnm'}= $f;
      last;
    }
  }

  bless $obj, $class;

  $obj->set (@_);

  $obj;
}

sub set
{
  my $self= shift;
  my %par= @_;

  my %res;
  foreach my $par (keys %par)
  {
    $res{$par}= $self->{$par};
    $self->{$par}= $par{$par};
  }

  (wantarray) ? %res : \%res;
}

sub parse_args
{
  my $self= shift;
  my @ARGV= @_;

  binmode (STDOUT, ':utf8');
  binmode (STDERR, ':utf8');

  my @PARS;
  my @extra_options;

  while (defined (my $arg= shift (@ARGV)))
  {
    # print __LINE__, " arg=[$arg]\n";

    if ($arg eq '--') { push (@PARS, @ARGV); @ARGV= (); }
    elsif ($arg =~ /^--(.+)/)
    {
      my ($opt, $val)= split ('=', $1, $2);

         if ($opt eq 'help')     { usage('help', 'usage'); exit(0); }
      elsif ($opt eq 'config')   { $self->{cfg_fnm}=      $val || shift (@ARGV); }
      elsif ($opt eq 'stanza')   { $self->{cfg_stanza}=   $val || shift (@ARGV); }
      elsif ($opt eq 'project')  { $self->{project_name}= $val || shift (@ARGV); }
      elsif ($opt eq 'out')      { $self->{out_csv}=      $val || shift (@ARGV); }
      # TODO: allow extra arguments for plugins or otherwise
      else { usage('error', "unknown option --${arg}"); exit(0); }
    }
    elsif ($arg =~ /^-(.+)/)
    {
      foreach my $opt (split ('', $1))
      {
        if ($opt eq 'h') { usage('help', 'usage'); exit (0); exit(0); }
        # elsif ($opt eq 'x') { $x_flag= 1; }
        else { usage('error', "unknown option -{$arg}"); }
      }
    }
    else
    {
      push (@PARS, $arg);
    }
  }

  unless (defined ($self->{op_mode}))
  {
    $self->{op_mode}= (@PARS) ? shift (@PARS) : 'help';
  }

  $self->{_pars}= \@PARS;

  1;
}

sub init
{
  my $self= shift;

  $self->{_cfg}=    my $cfg=    Util::JSON::read_json_file ($self->{cfg_fnm});
  return undef unless (defined ($cfg));

  $self->{_rm_cfg}= my $rm_cfg= $cfg->{$self->{cfg_stanza}};

  # TODO: set defaults?

  foreach my $an (@env_vars)
  {
    if (!defined ($self->{$an}) && exists ($rm_cfg->{$an}))
    {
      my $av= $self->{$an}= $rm_cfg->{$an};
      # print "transcribing attribute='$an' ($av)\n";
    }
  }

  $self->{_rm_wrapper}= my $mRM= new Redmine::Wrapper ('cfg' => $rm_cfg);

  ($cfg, $mRM);
}

sub get_wrapper
{
  my $self= shift;

  my $mRM= $self->{_rm_wrapper};
}

sub main_part2
{
  my $self= shift;

  # print __LINE__, " self: ", Dumper ($self);

  my ($op_mode, $pars)= map { $self->{$_} } qw(op_mode _pars);

  # print "op_mode=[$op_mode]\n";

=begin comment

  # print __LINE__, " mRM: ", Dumper ($mRM);

  my $project_name= $self->{'project_name'} || $rm_cfg->{'project_name'};
  unless (defined ($project_name))
  { # TODO: look up project id in Redmine itself
    print "ATTN: no project name found in configuration!\n";
  }

  my $tr_id_task= $mRM->get_tracker_id('Task');
  print "tr_id_task=[$tr_id_task]\n";

  my $project_id= $rm_cfg->{project_ids}->{$project_name};
  unless (defined ($project_id))
  { # TODO: look up project id in Redmine itself
    print "ATTN: no project_id found in config for project_name=[$project_name]\n";
  }

=end comment
=cut

  interpret($self, $op_mode, $pars);
}

sub interpret
{
  my $self= shift;
  my $op_mode= shift;
  my $pars= shift;

  my $mRM= $self->{_rm_wrapper};

  unless (defined ($mRM))
  {
    print "ATTN: Redmine::Wrapper not defined!\n";
    return undef;
  }

     if ($op_mode eq 'help') { usage('help', (@$pars) ? shift (@$pars) : 'overview'); }
  elsif ($op_mode eq 'exit') { return 0; }
  elsif ($op_mode eq 'interact' || $op_mode eq 'i')
  {
    $self->interact ();
  }
  elsif ($op_mode eq 'env')
  {
    foreach my $an (@env_vars)
    {
      printf ("%-15s = '%s'\n", $an, $self->{$an});
    }
  }
  elsif ($op_mode eq 'set')
  {
    my $an= shift (@$pars);

    if (exists ($env_vars{$an}))
    {
      $self->{$an}= join (' ', @$pars);
    }
    else
    {
      usage ('error', "unknown environment variable '$an'", 'help', 'environment');
    }
  }
  elsif ($op_mode eq 'list')
  {
    my $rm= $mRM->attach();

    my $project_name= (@$pars) ? shift (@$pars) : $self->{project_name};

    print "project_name=[$project_name]\n";
    my $out_csv= $self->{out_csv};
    Redmine::CLI::show_issues ($rm, $project_name, $out_csv);
  }
  elsif ($op_mode eq 'show')
  {
    my $rm= $mRM->attach();
    push (@$pars, $self->{ticket_number}) if (!@$pars && exists ($self->{ticket_number}));
    foreach my $ticket_number (@$pars)
    {
      Redmine::CLI::show_issue ($rm, $ticket_number);
      $self->{ticket_number}= $ticket_number;
    }
  }
  elsif ($op_mode eq 'browse' || $op_mode eq 'display')
  {
    my $rm_cfg= $self->{_rm_cfg};
    my $base_url= sprintf ("%s://%s/issues/", map { $rm_cfg->{$_} } qw(protocol host));

    push (@$pars, $self->{ticket_number}) if (!@$pars && exists ($self->{ticket_number}));
    foreach my $ticket_number (@$pars)
    {
      my $url= $base_url . $ticket_number;
      system ('xdg-open', $url);
    }
  }
  elsif ($op_mode eq 'parent')
  {
    my $rm= $mRM->attach();
    my $ticket_number= (@$pars) ? shift (@$pars) : $self->{ticket_number};

    print "ticket_number: $ticket_number\n";
    my $issue= $rm->issue( $ticket_number );

    if (defined ($issue) && exists ($issue->{issue}->{parent}))
    {
      print "issue: ", join (' ', sort keys %{$issue->{issue}}), "\n";
      my $parent= $issue->{issue}->{parent};
      print "parent issue: $parent ", Dumper ($parent);
      my $parent_issue= $parent->{id};
      $self->interpret ('show', [ $parent_issue ]);
    }
    else
    {
      print "no parent issue found for $ticket_number\n";
    }
  }
  elsif ($op_mode eq 'prepare')
  {
    my $project_name= $self->{project_name};
    my $tracker_name= $self->{tracker_name};
    my $subject= $self->{subject};
    my $description;

    my $t= prepare_ticket ($mRM, $project_name, $tracker_name, $subject, $description);
  }

=begin comment

not needed?
  elsif ($op_mode eq 'related')
  {
    my $rm= $mRM->attach();
    my $ticket_number= (@$pars) ? shift (@$pars) : $self->{ticket_number};

    print "ticket_number: $ticket_number\n";
    my $issue= $rm->issue( $ticket_number, { include => 'relations,changesets' } );

    if (defined ($issue))
    {
      print "issue: ", Dumper ($issue);
    }
  }

=end comment
=cut

  return 1;
}

sub interact
{
  my $self= shift;

  my $last_line;
  LINE: while (1)
  {
    print "rcli> ";
    my $l= <STDIN>;
    last unless (defined ($l));
    chop ($l);

    if ($l eq '.') { $l= $last_line }
    elsif ($l eq '') { next LINE; }
    else { $last_line= $l }

    my ($op, @pars)= split (' ', $l);
    print "op=[$op]\n";
    my $continue= interpret ($self, $op, \@pars);
    last unless ($continue);
  }
}

=head1 methods belonging WebService::Redmine

=cut

sub show_issues
{
  my $rm= shift;
  my $proj_name= shift;
  my $save_as_tsv= shift;

  print "rm=[$rm]\n";
  my $proj= $rm->project($proj_name);
  print "proj_name=[$proj_name] proj: ", Dumper ($proj);

  my $project_id= $proj->{'project'}->{'id'};
  # print "project_id=[$project_id]\n";

  my (@data, @rows);
  my $row_count= 0;
  my @columns1= qw(id tracker status subject assigned_to updated_on);
  my @columns2= qw(Issue Tracker Status Subject Assigned_to Updated_on);

  my $offset= 0;
  while (1)
  {
    my $issues= $rm->issues( { project_id => $project_id, offset => $offset } );
    # print "issues: ", Dumper ($issues);
    my ($i_off, $i_tc, $i_lim)= map { $issues->{$_} } qw(offset total_count limit);
    printf ("offset=%d total_count=%d limit=%d\n", $i_off, $i_tc, $i_lim);

    foreach my $issue (@{$issues->{'issues'}})
    {
      my ($rec_a, $rec_h)= filter1($issue, \@columns1);
      # print "rec: ", main::Dumper ($rec);
      push (@rows, $rec_a);
      push (@data, $rec_h);
      $row_count++;
    }

    last if (($offset= $i_off + $i_lim) >= $i_tc);
  }

  my $csv= new Util::Simple_CSV ('UTF8' => 1, verbose => 1);
  $csv->define_columns (@columns1);

  # print "rows: ", Dumper (\@rows);

  # Util::Matrix::print (\@columns2, \@rows);

  $csv->{rows}= \@rows;
  $csv->{data}= \@data;
  $csv->{row_count}= $row_count;
  # print "csv: ", Dumper ($csv);
  # $csv->sort ('id', 0, 1);
  $csv->sort ('subject', 0, 0);

  $csv->matrix_view (\@columns1);

  if (defined ($save_as_tsv))
  {
    print "saving tsv file to '$save_as_tsv'\n";
    $csv->save_csv_file (separator => "\t", filename => $save_as_tsv);
  }
}

sub filter1
{
  my $rec= shift;
  my $fields= shift;

  my @dx= ();
  my %dy= ();

  foreach my $field (@$fields)
  {
    my $x= $rec->{$field};
    $x= $x->{'name'} if (ref ($x) eq 'HASH');
    $dy{$field}= $x;

    push (@dx, $x);
  }
  (\@dx, \%dy);
}

=head1 methods belonging Redmine::Wrapper

=cut

sub prepare_ticket
{
  my $mRM= shift;
  my $project_name= shift;
  my $tracker_name= shift;
  my $subject= shift;
  my $description= shift;

  my $rm= $mRM->attach();

  # print "rm=[$rm]\n";

  my $proj_id= $mRM->get_project_id($project_name);
  # my $proj_id= $proj->{'project'}->{'id'};
  print "project_name=[$project_name] proj_id=[$proj_id]\n";

  my $tr_id= $mRM->get_tracker_id($tracker_name);
  # print "tr: ", Dumper ($tr);
  # my $tr_id= $tr->{'tracker'}->{'id'};
  print "tracker_name=[Task] tr_id=[$tr_id]\n";

  my $ticket=
  {
    issue => my $issue=
    {
      'project_id' => $proj_id,
      'tracker_id' => $tr_id,
      'subject' => $subject,
      'description' => $description,
    }
  };

  # print "ticket: ", Dumper ($ticket);

  $ticket;
}

sub show_issue
{
  my $rm= shift;
  my $ticket_number= shift;

  my $issue= $rm->issue( $ticket_number, { include => 'children,attachments,relations,changesets,journals' } );
  print "issue: ", Dumper ($issue);
  $issue;
}

sub usage
{
  my $type= shift || 'help';
  my $message= shift || 'usage';

  my $pod= new Pod::Simple::Text();
  my $y= $pod->output_fh (*STDOUT);

  # print "usage: type=[$type] message=[$message]\n";

  my $was_error= 0;
  while (1)
  {
    if ($type eq 'error')
    {
      $was_error= 1;
      print "ERROR: ", $message, "\n\n";
    }
    elsif ($type eq 'help')
    {
      $message= 'overview' unless (exists ($HELP{$message}));
      $pod->parse_string_document ($HELP{$message});
    }

    last unless (@_);
  }

  # system ('perldoc', __FILE__);
}

1;

__END__

=head1 TODOS

=over 1

=item The command line options need to be evolved

=back

=head1 AUTHOR

Gerhard Gonter E<lt>ggonter@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2016 by Gerhard Gonter

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut

