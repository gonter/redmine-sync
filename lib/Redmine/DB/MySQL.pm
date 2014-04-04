
package Redmine::DB::MySQL;

use strict;
use parent 'Redmine::DB';

# use Redmine::DB::Project;

my $show_fetched= 0;

sub connect
{
  my $self= shift;

  my $dbh= $self->{'_dbh'};
  return $dbh if (defined ($dbh));

  my $db_con= join (':', 'dbi', map { $self->{$_} } qw(adapter database host));
  print "db_con=[$db_con]\n";
  $dbh= DBI->connect($db_con, map { $self->{$_} } qw(username password));
  print "dbh=[$dbh]\n";
  $self->{'_dbh'}= $dbh;
}

sub table
{
  my $self= shift;
  my $table= shift;

  my $t= $self->{$table};
     $t= $self->{$table}= {} unless (defined ($t));
  # print "accessing table=[$table]: ", main::Dumper($self);
  $t;
}

sub get_all_x
{
  my $self= shift;
  my $table= shift;
  my $where= shift;

  my $dbh= $self->connect();
  return undef unless (defined ($dbh));

  # my $project= new Redmine::DB::Project (%par);
  # print "project: ", main::Dumper ($project);

  my $ss = qq/SELECT * FROM $table/;

  my @v= ();
  if (defined ($where))
  {
    print "where: ", main::Dumper ($where);
    $ss .= ' WHERE ' . shift (@$where);
    @v= @$where;
  }
  print "ss=[$ss]\n";

  my $sth= $dbh->prepare($ss) or print $dbh->errstr;
  print "sth=[$sth]\n";
  $sth->execute(@v);

  my $t= $self->table($table);

  while (defined (my $x= $sth->fetchrow_hashref()))
  {
    print "x: ", main::Dumper ($x) if ($show_fetched);
    $t->{$x->{'id'}}= $x;
  }

  $t;
}

=head1 REDMINE STUFF

before that, this might be usable for other Rails applications

TODO: factor out...

=cut

sub get_all_projects { shift->get_all_x ('projects'); }
sub get_all_users    { shift->get_all_x ('users'); }

sub get_project_members
{
  my $self= shift;
  my $proj_id= shift;

  $self->get_all_x ('members', [ 'project_id=?', $proj_id ]);
}

=head1 REDMINE SYNC STUFF

=cut

sub get_members
{
  my $self= shift;
  my $proj_id= shift;

  my $res= $self->table('x_sync');

  my $proj=    $self->get_all_x ('projects', [ 'id=?',         $proj_id ]);
  my $members= $self->get_all_x ('members',  [ 'project_id=?', $proj_id ]);
  $res->{'project'}= $proj;
  $res->{'members'}= $members;

  print "proj: ", main::Dumper($proj);

  # --------------------------------------------------------------------
  # check for members and users
  my $users= $self->table('users');
  # print "users: ", main::Dumper($users);
  my @missing_users=();
  foreach my $member_id (keys %$members)
  {
    # my $member= $members->{$member_id};
    # my $user_id= $member->{'user_id'};
    my $user_id= $members->{$member_id}->{'user_id'};

    push (@missing_users, $user_id) unless (exists ($users->{$user_id}));
    # last if (@missing_users > 3);
  }

  if (@missing_users)
  {
    print "missing users: [", join (' ', @missing_users), "]\n";
    my $in= 'id IN ('. join(',', map { '?' } @missing_users) . ')';
    # $show_fetched= 1;
    $self->get_all_x ('users', [ $in, @missing_users ]),
  }

  $res;
}

sub get_wiki
{
  my $self= shift;
  my $proj_id= shift;

  my $res= $self->table('x_sync');

  # --------------------------------------------------------------------
  # check for wiki stuff
  my $wikis= $self->get_all_x ('wikis',    [ 'project_id=?', $proj_id ]);
  if (defined ($wikis))
  {
    $res->{'wikis'}= $wikis;

    # CHECK: there shouldn't be more than wiki per project, right?
    my @wiki_ids= keys %$wikis;
    if (@wiki_ids > 1)
    {
      print "ATTN: too many(?) wikis for project=$proj_id ";
      print main::Dumper ($wikis);
    }

    foreach my $wiki_id (@wiki_ids)
    {
      my $wiki_pages= $self->get_all_x ('wiki_pages', [ 'wiki_id=?', $proj_id ]);
      print "wiki_id=[$wiki_id] wiki_pages: ", main::Dumper ($wiki_pages);
    }
  }

  $res;
}

1;
__END__


