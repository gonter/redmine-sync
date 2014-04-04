#!/usr/bin/perl

use strict;
use warnings;

=head1 NAME

 t_sync.pl

=head1 DESCRIPTION

do stuff on a Redmine database

=head1 OPERATION MODES

=cut

use lib 'lib';

binmode( STDOUT, ':utf8' );

use YAML::Syck;
# use XML::LibXML;
use DBI;
use DBD::mysql;
use Encode;
use Data::Dumper;
$Data::Dumper::Indent= 1;

use Redmine::DB::MySQL;
# use Redmine::DB::Project; nothing here yet ...

# yeah, this should be in a config file, but 
my $setup_file;
my $setup=
{
  'src' =>
  {
    'config' => '/home/gg/etc/src/database.yml',
    'db' => 'production',
  },
  'dst' =>
  {
    'config' => '/home/gg/etc/dst/database.yml',
    'db' => 'production',
  },
  'sync_projects' =>
  [
    {
      'src_proj' => 170,
      'dst_proj' => 1,
    }
  ]
};

my @parameters= ();
my $op_mode= 'usage';
my %op_modes= map { $_ => 1 } qw(sync sdp prep);

while (my $arg= shift (@ARGV))
{
     if ($arg eq '--') { push (@parameters, @ARGV); @ARGV= (); }
  elsif ($arg =~ m#^--(.+)#)
  {
    my $opt= $1;
    # print "opt=[$opt]\n";
    if (exists ($op_modes{$opt})) { $op_mode= $opt; }
    elsif ($opt eq 'help') { usage(); }
    else { die "unknown option [$opt]"; }
  }
  elsif ($arg =~ m#^-(.+)#)
  {
    my @opts= split ('|', $1);
    # print "opts: ", Dumper (\@opts);
    foreach my $opt (@opts)
    {
      if ($opt eq 'h') { usage(); }
      else { die "unknown option [$opt]"; }
    }
  }
  else { push (@parameters, $arg); }
}

sub usage
{
  system ('perldoc', $0);
  exit (0);
}

if ($op_mode eq 'usage') { usage(); }
elsif ($op_mode eq 'prep')
{
  my $dst= read_configs($setup, 'dst');
  prepare_sync_table ($dst);
}
elsif ($op_mode eq 'sdp')
{
  my $dst= read_configs($setup, 'dst');

  my $dst_proj= $dst->get_all_projects();
  print "dst_proj: ", Dumper ($dst_proj);
}
elsif ($op_mode eq 'sync')
{
  my $src= read_configs($setup, 'src');
  my $dst= read_configs($setup, 'dst');

  # print "setup: ", Dumper ($setup);

  foreach my $sp (@{$setup->{'sync_projects'}})
  {
    print "sp: ", Dumper ($sp);
    my $sx= $src->get_project_members ($sp->{'src_proj'});
    print "sx: ", Dumper ($sx);
  }
}
elsif ($op_mode eq 'diag')
{
  my $src= read_configs($setup, 'src');
  my $dst= read_configs($setup, 'dst');
  # print "setup: ", Dumper ($setup);

  # my $src_proj= $src->get_all_projects();
  # print "src_proj: ", Dumper ($src_proj);

# my $src_usr= $src->get_all_users();
# print "src_usr: ", Dumper ($src_usr);
# print "src: ", Dumper ($src);

# my $src_members= $src->get_project_members (170);
# print "src_members: ", Dumper ($src_members);


# print "src: ", Dumper ($src);
}
else
{
  die("unknown op_mode=[$op_mode]");
}

exit (0);

sub read_configs
{
  my $stp= shift;
  my $s= shift;

    my $ss= $stp->{$s};

    my ($yml, $db)= map { $ss->{$_} } qw(config db);

    print "s=[$s] yml=[$yml] db=[$db]\n";
    my $x= YAML::Syck::LoadFile ($yml);
    # $ss->{'_cfg'}=
    my $c= $x->{$db};

  $c->{'adapter'}= 'mysql' if ($c->{'adapter'} eq 'mysql2');
  my $m= new Redmine::DB::MySQL (%$c);

  $ss->{'m'}= $m;
  my $dbh= $m->connect();

  $m;
}

sub prepare_sync_table
{
  my $con= shift;

  my $dbh= $con->connect();
  print "dbh=[$dbh]\n";

  my $ss= <<'EOX';
CREATE TABLE `syncs`
(
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `context_id` int(11) DEFAULT NULL,
  `table` varchar(255) DEFAULT NULL,
  `src_id` int(11) DEFAULT NULL,
  `dst_id` int(11) DEFAULT NULL,
  `sync_date` datetime DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8;
EOX

  print "perform this on the database\n", "--- 8< ---\n", $ss, "--- >8 ---\n";
}
