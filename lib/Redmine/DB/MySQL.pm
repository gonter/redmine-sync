
package Redmine::DB::MySQL;

use strict;
use parent 'Redmine::DB';

use Data::Dumper;

# use Redmine::DB::Project;

my $show_query= 0;
my $show_fetched= 0;
my $show_updates= 0;

sub show_fetched { shift; my $ret= $show_fetched; $show_fetched= shift; $ret; }
sub show_query   { shift; my $ret= $show_query;   $show_query=   shift; $ret; }
sub show_updates { shift; my $ret= $show_updates; $show_updates= shift; $ret; }
sub verbose      { shift; my @ret= ($show_fetched, $show_query, $show_updates); $show_fetched= $show_query= $show_updates= shift; @ret; }

sub connect
{
  my $self= shift;

  my $dbh= $self->{'_dbh'};
  return $dbh if (defined ($dbh));

  my $adapter= $self->{adapter};
  $adapter= 'mysql' if ($adapter eq 'mysql2');

  my $db_con= join (':', 'dbi', $adapter, map { $self->{$_} } qw(database host));
  # print "db_con=[$db_con]\n";
  $dbh= DBI->connect($db_con, map { $self->{$_} } qw(username password));
  # print "dbh=[$dbh]\n";
  $self->{'_dbh'}= $dbh;
}

sub table
{
  my $self= shift;
  my $table= shift;

  my $t= $self->{$table};
     $t= $self->{$table}= {} unless (defined ($t));
  # print "accessing table=[$table]: ", Dumper($self);
  $t;
}

=head2 $con->get_all_x ($table_name, $query_ref, $field_ref)

Query_ref is an array reference where the first parameter gives the WHERE clause (without the string "WHERE").
The query should not contain untrustable values, these should be indicated by placeholders (an "?" for each
value).  The values make up the rest of the array reference.

Side effect: caches values in $con->{$table_name};

Returns all retrieved records.

=cut

sub get_all_x
{
  my $self= shift;
  my $table= shift;
  my $where= shift;
  my $field_ref= shift || '*';

  my $dbh= $self->connect();
  return undef unless (defined ($dbh));

  my $ss= "SELECT $field_ref FROM $table";

  my @v= ();
  if (defined ($where))
  {
    # print "where: ", Dumper ($where) if ($show_query);
    @v= @$where; # copy first!
    $ss .= ' WHERE ' . shift (@v);
  }

  if ($show_query)
  {
    print "ss=[$ss]";
    print ' vars: ', join (',', @v) if (@v);
    print "\n";
  }

  my $sth= $dbh->prepare($ss) or print $dbh->errstr;
  # print "sth=[$sth]\n";
  my $rc= $sth->execute(@v);
  # print __LINE__, "rc=[$rc]\n";
  unless (defined ($rc))
  {
    print __LINE__, " rc=[$rc] ", $dbh->errstr(), "\n";
    print __LINE__, " caller: ", join (' ', caller()), "\n";
    return undef;
  }

  my $t= $self->table($table);
  my $tt= {};

  my $pri= (exists ($self->{PRI}->{$table})) ? $self->{PRI}->{$table} : 'id';
  # print __LINE__, " pri=[$pri] ", main::Dumper ($self->{PRI});
  # print __LINE__, " pri=[$pri]\n";

  while (defined (my $x= $sth->fetchrow_hashref()))
  {
    print "x: ", Dumper ($x) if ($show_fetched);
    my $i= $x->{$pri};
    $t->{$i}= $tt->{$i}= $x;
  }

  $tt;
}

sub delete_all_x
{
  my $self= shift;
  my $table= shift;
  my $where= shift;
  my $field_ref= shift || '*';

  my $dbh= $self->connect();
  return undef unless (defined ($dbh));

  my $ss= "DELETE $field_ref FROM $table";

  my @v= ();
  if (defined ($where))
  {
    # print "where: ", Dumper ($where) if ($show_query);
    $ss .= ' WHERE ' . shift (@$where);
    @v= @$where;
  }

  if ($show_query)
  {
    print "ss=[$ss]";
    print ' vars: ', join (',', @v) if (@v);
    print "\n";
  }

  my $sth= $dbh->prepare($ss) or print $dbh->errstr;
  # print "sth=[$sth]\n";
  $sth->execute(@v);
}

sub tables
{
  my $self= shift;

  my $dbh= $self->connect();
  return undef unless (defined ($dbh));

  my $ss= "SHOW TABLES";

  if ($show_query)
  {
    print "ss=[$ss]\n";
  }

  my $sth= $dbh->prepare($ss) or print $dbh->errstr;
  # print "sth=[$sth]\n";
  $sth->execute();

  my $table_filter= $self->{table_filter};

  my $table_names= $self->{table_names}= {};
  while (defined (my $table_name= $sth->fetchrow_array()))
  {
    next if (defined ($table_filter) && &$table_filter($table_name) == 0);
    $table_names->{$table_name}= undef;
  }

  $table_names;
}

sub desc_all
{
  my $self= shift;

  my $table_names= $self->tables();

  foreach my $table_name (sort keys %$table_names)
  {
    $self->desc($table_name);
  }
}

sub desc
{
  my $self= shift;
  my $table= shift;

  my $dbh= $self->connect();
  return undef unless (defined ($dbh));

  my $ss= "DESC `$table`";

  if ($show_query)
  {
    print "ss=[$ss]\n";
  }

  my $sth= $dbh->prepare($ss) or print $dbh->errstr;
  # print "sth=[$sth]\n";
  $sth->execute();

  # get table definition
  my $td= $self->{table_names}->{$table};
  my $td= $self->{table_names}->{$table}= {} unless (defined ($td));
  my $tt= $td->{'columns'}= [];

  # my @desc_columns= qw(Field Type Null Key Default Extra);

  while (my @x= $sth->fetchrow_array())
  {
    last unless (@x);
    # print "x: ", Dumper (\@x); # if ($show_fetched);
    push (@$tt, \@x);

    if ($x[3] eq 'PRI')
    {
      $self->{PRI}->{$table}= $x[0];
    }
  }

  $td;
}

sub insert
{
  my $self= shift;
  my $table= shift;
  my $record= shift;

  my $dbh= $self->connect();
  return undef unless (defined ($dbh));

  my (@vars, @vals);
  foreach my $an (keys %$record)
  {
    push (@vars, $an);
    push (@vals, $record->{$an});
  }

  my $ssi= "INSERT INTO `$table` (". join (',', @vars) .") VALUES (" . join(',', map { '?' } @vars) . ")";
  print "ssi=[$ssi]\n";
  print "vals: ", join (',', @vals), "\n";
  my $sth= $dbh->prepare($ssi);
  my $rc= $sth->execute(@vals);
  unless (defined ($rc))
  {
    print __LINE__, " rc=[$rc] ", $dbh->errstr(), "\n";
    print __LINE__, " caller: ", join (' ', caller()), "\n";
    return undef;
  }

  print "ERROR: ", $dbh->errstr() if ($dbh->err);
  $sth->finish();

  return $record->{'id'} if (defined ($record->{'id'})); # id attribute was set already

  my $ssq= "SELECT LAST_INSERT_ID()";
  print "ssq=[$ssq]\n";
  $sth= $dbh->prepare($ssq);
  $sth->execute();
  print "ERROR: ", $dbh->errstr() if ($dbh->err);
  my ($id)= $sth->fetchrow_array();
  print "INSERT: id=[$id]\n";

  $id;
}

sub update
{
  my $self= shift;
  my $table= shift;
  my $id= shift;
  my $updates= shift;

  my $dbh= $self->connect();
  return undef unless (defined ($dbh));

  my (@vars, @vals);
  foreach my $an (keys %$updates)
  {
    push (@vars, $an);
    push (@vals, $updates->{$an});
  }
  push (@vals, $id);

  my $pri= (exists ($self->{PRI}->{$table})) ? $self->{PRI}->{$table} : 'id';
  # print __LINE__, " pri=[$pri] ", main::Dumper ($self->{PRI});
  # print __LINE__, " pri=[$pri]\n";

  my $ssu= "UPDATE `$table` SET ". join (', ', map { $_.'=?' } @vars) . " WHERE `$pri`=?"; # Hmm... WHERE ?=?

  if ($show_updates)
  {
    print "ssu=[$ssu]\n";
    print "vals: ", join (',', @vals), "\n";
  }

  my $sth= $dbh->prepare($ssu);
  my $rc= $sth->execute(@vals);

  unless (defined ($rc))
  {
    print __LINE__, " rc=[$rc] ", $dbh->errstr(), "\n";
    print __LINE__, " caller: ", join (' ', caller()), "\n";
    return undef;
  }

  $sth->finish();
}

sub mysql
{
  my $self= shift;
  print "self: ", Dumper ($self);

  $ENV{MYSQL_PWD}= $self->{password};
  my @cmd= ('mysql', '-h', $self->{'host'}, '-u', $self->{'username'}, $self->{'database'});
  print ">> cmd=[", join (' ', @cmd), "]\n";
  system (@cmd);
}

=head1 REDMINE STUFF

before that, this might be usable for other Rails applications

TODO: factor out...

=cut

sub get_all_projects { shift->get_all_x ('projects'); }
sub get_all_users    { shift->get_all_x ('users'); }

sub get_user
{
  my $self= shift;
  my $an= shift;
  my $av= shift;

  my $res= $self->get_all_x ('users', [ $an.'=?', $av ]);
}

sub get_users
{
  my $self= shift;
  my $an= shift;

  # print "missing users: [", join (' ', @missing_users), "]\n";
  my $in= $an . ' IN ('. join(',', map { '?' } @_) . ')';
  # $show_query= $show_fetched= 1;
  $self->get_all_x ('users', [ $in, @_ ]),
}

sub get_project_members
{
  my $self= shift;
  my $proj_id= shift;

  $self->get_all_x ('members', [ 'project_id=?', $proj_id ]);
}

=head1 REDMINE SYNC STUFF

=cut

sub pcx_members
{
  my $self= shift;
  my $proj_id= shift;

  my $res= $self->table('pcx');

  my $proj=    $self->get_all_x ('projects', [ 'id=?',         $proj_id ]);
  my $members= $self->get_all_x ('members',  [ 'project_id=?', $proj_id ]);

  $res->{'project'}= $proj;
  $res->{'members'}= $members;

  # print "proj: ", Dumper($proj);

  # --------------------------------------------------------------------
  # check for members and users
  my $users= $self->table('users');
  # print "users: ", Dumper($users);
  my @missing_users=();
  foreach my $member_id (keys %$members)
  {
    # my $member= $members->{$member_id};
    # my $user_id= $member->{'user_id'};
    my $user_id= $members->{$member_id}->{'user_id'};

    push (@missing_users, $user_id) unless (exists ($users->{$user_id}));
    # last if (@missing_users > 3);
  }

  $res->{'users'}= $self->get_users ('id', @missing_users) if (@missing_users);

  $res;
}

=head2 $con->pcx_wiki ($project_id)

Retrieve data related to the Wiki associated with $project_id.

Right now, we assume we can handle the amount of data returned, see
notes in the code.

=cut

sub pcx_wiki
{
  my $self= shift;
  my $proj_id= shift;

  my $res= $self->table('pcx');

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
      print Dumper ($wikis);
    }

    PROJECT_WIKI: foreach my $wiki_id (@wiki_ids)
    {
      my $wiki_pages= $self->get_all_x ('wiki_pages', [ 'wiki_id=?', $wiki_id ]);
      # $res->{'wiki_pages'}->{$wiki_id}= $wiki_pages; # one layer too many!
      $res->{'wiki_pages'}= $wiki_pages;
      # print "wiki_id=[$wiki_id] wiki_pages: ", Dumper ($wiki_pages);

      my $wiki_redirects= $self->get_all_x ('wiki_redirects', [ 'wiki_id=?', $wiki_id ]);
      # $res->{'wiki_redirects'}->{$wiki_id}= $wiki_redirects;
      $res->{'wiki_redirects'}= $wiki_redirects;

      # fetch the Wiki text
      # TODO: for now, assume we can handle the amount of data returned;
      # it might be necessary to introduce callbacks deal with the text

      my $sel_wiki_pages= '(SELECT id FROM wiki_pages WHERE wiki_id=?)';
      my $wiki_contents=         $self->get_all_x ('wiki_contents',         [ 'page_id IN ' . $sel_wiki_pages, $wiki_id ]);
      my $wiki_content_versions= $self->get_all_x ('wiki_content_versions', [ 'page_id IN ' . $sel_wiki_pages, $wiki_id ]);
      $res->{'wiki_contents'}=         $wiki_contents;
      $res->{'wiki_content_versions'}= $wiki_content_versions;

      # attachments
      my $sel2= 'container_id IN ' . $sel_wiki_pages . " AND container_type='WikiPage'";
      my $wiki_attachments=       $self->get_all_x ('attachments', [ $sel2, $wiki_id ]);
      $res->{'wiki_attachments'}= $wiki_attachments;

      # watchers
$show_query= 1;
      my $wiki_watchers=       $self->get_all_x ('watchers', [ "watchable_type='Wiki' AND watchable_id=?", $wiki_id ]);
      my $wiki_page_watchers=  $self->get_all_x ('watchers', [ "watchable_type='WikiPage' AND watchable_id IN ".$sel_wiki_pages, $wiki_id ]);

      $res->{'wiki_watchers'}= $wiki_watchers;
      $res->{'wiki_page_watchers'}= $wiki_page_watchers;

      last PROJECT_WIKI; # TODO: hmm... I really should check if there could be more than one wiki per project
    }
  }

  $res;
}

sub pcx_user_preferences
{
  my $self= shift;
  my $proj_id= shift;

  my $res= $self->table('pcx');

  # $show_query= 1;
  my $pref= $self->get_all_x ('user_preferences', [ 'user_id in (select user_id from members where project_id=?)', $proj_id ]);

  $res->{'user_preferences'}= $pref;

  $res;
}

sub fetch_custom
{
  my $db= shift;
  my $cfid= shift;
  my $cfty= shift || 'Issue';

  my $res= $db->get_all_x ('custom_values',
      [ "custom_field_id=? and customized_type=?", $cfid, $cfty ]);
  $res;
}

sub change_custom_value
{
  my $db= shift;
  my $cfid= shift;
  my $cfty= shift || 'Issue';
  my $cfref= shift; # ticket number or whatever
  my $cfrid= shift; # record id
  my $cfval= shift;

  my $data=
      { customized_type => $cfty, customized_id => $cfref,
        custom_field_id => $cfid, value => $cfval };

  print "change_custom_value: cfrid=[$cfrid] ", join (' ', %$data), "\n";
  # return 0; # TODO: add flag to supress changes

  my $res;
  if (defined ($cfrid))
  {
    $db->update ('custom_values', $cfrid, $data);
    $res= $cfrid;
  }
  else
  {
    $res= $db->insert ('custom_values', $data);
  }

  $res;
}

1;
__END__


