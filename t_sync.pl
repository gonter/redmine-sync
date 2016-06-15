#!/usr/bin/perl

use strict;
use warnings;

=head1 NAME

 t_sync.pl

=head1 DESCRIPTION

Do stuff on a Redmine MySQL database.  Used as an experimental sync-tool
to migrate individual projects to another instance.

See https://github.com/gonter/redmine-sync

=head1 OPERATION MODES

--mysql <src|dst>  ... connect to source or destinance instance's MySQL databae

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
use Redmine::DB::CTX;
# use Redmine::DB::Project; nothing here yet ...

# --- BEGIN ------------------------------------------------------------

=begin comment

Yeah, this should be in a config file, but this will do for now.

This structure ($setup) resembles something like a "synchronisation
context".  A "synchronisation context" needs to describe:

* src: source Redmine instance
* dst: destination Redmine instance
* projects to be synced

=end comment
=cut

my $setup_file;
my $setup=
{
  'src' =>
  {
    'config' => '/home/gg/etc/src/database.yml',
    'db'     => 'production',
    'attachment_base' => '/home/backup/redmine-phaidra/files',
    'attachment_with_directory' => 0, # Redmine version 1.x does not have that attribute
  },
  'dst' =>
  {
    'config' => '/home/gg/etc/dst/database.yml',
    'db'     => 'production',
    'attachment_base' => '/var/lib/redmine/default/files',
    'attachment_with_directory' => 1, # Redmine version 2.x has that attribute
  },
};

my $setup_OLD=
{
  'dst' =>
  {
    'config' => '/home/gg/etc/dst/database.yml',
    'db'     => 'production',
    'attachment_base' => '/var/lib/redmine/default/files',
    'attachment_with_directory' => 1, # Redmine version 2.x has that attribute
  },
  'sync_context_id' => 1,
  'syncs' => # not used, instead, this is written directly into the database
  [
    # { 'table' => 'projects', 'src_id' => 170, 'dst_id' => 1 }
    { 'table' => 'auth_sources', 'src_id' => 1, 'dst_id' => 1 }
  ],
  'sync_projects' =>
  [
    {
      'src_proj' => 170,
      'dst_proj' => 2, # we could try to retrieve a translation here
    }
  ]
};
# --- END --------------------------------------------------------------

my @parameters= ();
my $op_mode= 'usage';
my %op_modes= map { $_ => 1 } qw(sync sdp prep auth mysql user syncuser);

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
      elsif ($opt eq 'X') { $setup= $setup_OLD; }
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

# callback function to actually copy the attachment files
# NOTE/TODO: be sure about the permissions, this script needs to write into Redmine's files directory
sub copy_attachment
{
  my $ctx=    shift;
  my $orig=   shift;  # original record
  my $synced= shift;  # synchronized record

  my @s_fnm= $setup->{'src'}->{'attachment_base'}; # TODO/NOTE: hmm... the attachment_base doesn't make it into the context!
  push (@s_fnm, $orig->{'disk_directory'}) if (exists ($orig->{'disk_directory'}) && defined ($orig->{'disk_directory'}));
  push (@s_fnm, $orig->{'disk_filename'});
  my $s_fnm= join ('/', @s_fnm);
  # TODO: check if the file is there and stuff

  my @d_fnm= $setup->{'dst'}->{'attachment_base'};

  # if (exists ($synced->{'disk_directory'})) # ... && defined ($synced->{'disk_directory'}))
  if ($setup->{'dst'}->{'attachment_with_directory'})
  { # new Redmine version has a structured attachments directory
    my $disk_dir= join ('/', 'sync', $setup->{'sync_context_id'});
    push (@d_fnm, $disk_dir);
    $ctx->{'dst'}->update ('attachments', $synced->{'id'}, { 'disk_directory' => $disk_dir });
  }

  my $d_fnm= join ('/', @d_fnm);
  system ('mkdir', '-p', $d_fnm) unless (-d $d_fnm);
  $d_fnm .= '/'.  $synced->{'disk_filename'};

  print "copy attachment [$s_fnm] -> [$d_fnm]\n";

  system ('cp', $s_fnm, $d_fnm);
}

   if ($op_mode eq 'usage') { usage(); }
elsif ($op_mode eq 'prep')
{
  my $dst= read_configs($setup, 'dst');
  prepare_sync_table ($dst);
}
elsif ($op_mode eq 'sdp') # sdp: show destination instance's projects
{
  my $dst= read_configs($setup, 'dst');

  my $dst_proj= $dst->get_all_projects();
  print "dst_proj: ", Dumper ($dst_proj);
}
elsif ($op_mode eq 'mysql')
{
  my $target= shift (@parameters);
  usage() unless (defined ($target));
  my $env= shift (@parameters) || 'production';
  my $cfg= read_configs($setup, $target);
  $cfg->mysql();
}
elsif ($op_mode eq 'auth')
{
  my $src= read_configs($setup, 'src');
  my $dst= read_configs($setup, 'dst');

  $src->show_fetched (1);
  $src->get_all_x ('auth_sources');
  $dst->get_all_x ('auth_sources');
}
elsif ($op_mode eq 'user')
{
  my $target= shift (@parameters);
  usage() unless (defined ($target));

  my $an= shift (@parameters);
  usage() unless (defined ($an));

  my $cfg= read_configs($setup, $target);

  foreach my $av (@parameters)
  {
    my $user= $cfg->get_user ($an, $av);
    print "user: ", Dumper ($user);
  }
}
elsif ($op_mode eq 'syncuser')
{
  usage() unless (@parameters);

  my $src= read_configs($setup, 'src');
  my $dst= read_configs($setup, 'dst');
  # my $x_u= $src->get_all_users();

  my $ctx= new Redmine::DB::CTX ('ctx_id' => $setup->{'sync_context_id'}, 'src' => $src, 'dst' => $dst);
  my $res= $src->get_users ('login', @parameters);
  print "res: ", Dumper ($res);
  foreach my $s_user_id (keys %$res)
  {
    $ctx->sync_user ($s_user_id, $res->{$s_user_id});
  }
}
elsif ($op_mode eq 'cleanup')
{
  my $dst= read_configs($setup, 'dst');

  my $ctx= new Redmine::DB::CTX ('ctx_id' => $setup->{'sync_context_id'}, 'dst' => $dst);
  foreach my $sp (@{$setup->{'sync_projects'}})
  {
    # print "sp: ", Dumper ($sp);

print "not yet implemented\n";
    # $ctx->sync_cleanup_project ($sp->{'dst_proj'});
  }

  print "\n"x3, '='x72, "\n", "Statistics:", Dumper ($ctx->{'stats'});
}
elsif ($op_mode eq 'sync')
{
  my $src= read_configs($setup, 'src');
  my $dst= read_configs($setup, 'dst');
  # my $x_u= $src->get_all_users();

  my $ctx= new Redmine::DB::CTX ('ctx_id' => $setup->{'sync_context_id'}, 'src' => $src, 'dst' => $dst,
     'copy_attachment' => \&copy_attachment);

  # print "setup: ", Dumper ($setup);

  foreach my $sp (@{$setup->{'sync_projects'}})
  {
    print "sp: ", Dumper ($sp);

    $ctx->sync_project ($sp->{'src_proj'}, $sp->{'dst_proj'});
  }

  print "\n"x3, '='x72, "\n", "Statistics:", Dumper ($ctx->{'stats'});
}
elsif ($op_mode eq 'xxxdiag')
{
  my $src= read_configs($setup, 'src');
  my $dst= read_configs($setup, 'dst');
  # print "setup: ", Dumper ($setup);

  # my $src_proj= $src->get_all_projects();
  # print "src_proj: ", Dumper ($src_proj);

# my $src_usr= $src->get_all_users();
# print "src_usr: ", Dumper ($src_usr);
# print "src: ", Dumper ($src);

# my $src_members= $src->get_project_members (... some project id ...);
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

  # $c->{'adapter'}= 'mysql' if ($c->{'adapter'} eq 'mysql2');
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

  my ($ddl_sync_contexts, $ddl_syncs)= Redmine::DB::CTX::get_DDL();
  # NOTE: for some reason, this can't be sent to the database, maybe/probably I'm missing something...

  print "perform this on the database\n", "--- 8< ---\n",
        $ddl_sync_contexts, "\n",
        $ddl_syncs,
        "--- >8 ---\n";
}

__END__

=head1 TODO

 * currently, only MySQL source and targets were used, supporting
   PostgreSQL and/or sqlite would be nice as well


