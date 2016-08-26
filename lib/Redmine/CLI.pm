
=pod

=head1 NAME

  REdmine::CLI

=head1 DESCRIPTION

  experimental stuff for something like a Redmine command line interface

=cut

package Redmine::CLI;

use strict;

use Util::JSON;
use Util::Simple_CSV;
use Util::Matrix;

use Redmine::Wrapper;

use Data::Dumper;

my $default_config_fnm= 'redmine.json';
my @default_home_dirs= ('etc', undef, 'bin');

sub new
{
  my $class= shift;

  my $obj=
  {
     # defaults
     'cfg_stanza'   => 'Redmine',
     'op_mode'      => 'list',
     'project_name' => undef,
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
  my $obj= shift;
  my %par= @_;

  my %res;
  foreach my $par (keys %par)
  {
    $res{$par}= $obj->{$par};
    $obj->{$par}= $par{$par};
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

         if ($opt eq 'help')     { usage(); }
      elsif ($opt eq 'config')   { $self->{cfg_fnm}=      $val || shift (@ARGV); }
      elsif ($opt eq 'stanza')   { $self->{cfg_stanza}=   $val || shift (@ARGV); }
      elsif ($opt eq 'project')  { $self->{project_name}= $val || shift (@ARGV); }
      elsif ($opt eq 'show') { $self->{op_mode}= 'show'; }
      elsif ($opt eq 'list') { $self->{op_mode}= 'list'; }
      # TODO: allow extra arguments
      else { usage(); }
    }
    elsif ($arg =~ /^-(.+)/)
    {
      foreach my $opt (split ('', $1))
      {
         if ($opt eq 'h') { usage(); exit (0); }
        # elsif ($opt eq 'x') { $x_flag= 1; }
        else { usage(); }
      }
    }
    else
    {
      push (@PARS, $arg);
    }
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

  $self->{_rm_wrapper}= my $mRM= new Redmine::Wrapper ('cfg' => $rm_cfg);

  ($cfg, $mRM);
}

sub main_part2
{
  my $self= shift;

  # print __LINE__, " self: ", Dumper ($self);

  my ($mRM, $rm_cfg, $op_mode, $pars)= map { $self->{$_} } qw(_rm_wrapper _rm_cfg op_mode _pars);
  unless (defined ($mRM))
  {
    print "ATTN: Redmine::Wrapper not defined!\n";
    return undef;
  }

  # print __LINE__, " mRM: ", Dumper ($mRM);

  print "op_mode=[$op_mode]\n";
  my $project_name= $self->{'project_name'} || $rm_cfg->{'project-name'};
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

  if ($op_mode eq 'show')
  {
    my $rm= $mRM->attach();
    foreach my $ticket_number (@$pars)
    {
      Redmine::CLI::show_issue ($rm, $ticket_number);
    }
  }
  elsif ($op_mode eq 'list')
  {
    my $rm= $mRM->attach();
    print "project_name=[$project_name]\n";
    Redmine::CLI::show_issues ($rm, $project_name);
  }
}

sub show_issues
{
  my $rm= shift;
  my $proj_name= shift;

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

sub show_issue
{
  my $rm= shift;
  my $ticket_number= shift;

  my $issues= $rm->issue( $ticket_number );
  print "issues: ", Dumper ($issues);
}

sub usage
{
  system ('perldoc', __FILE__);
  exit (0);
}

1;

