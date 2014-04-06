
package Redmine::DB::CTX;

use strict;
use parent 'Redmine::DB';

sub sync_project
{
  my $ctx= shift;
  my $sp_id= shift;
  my $dp_id= shift;

  $ctx->sync_project_users ($sp_id, $dp_id);
}

=head2 $context->translate ($table_name, $src_id)

=cut

sub translate
{
  my $ctx= shift;
  my $table_name= shift;
  my $src_id= shift;

  unless (defined ($src_id))
  {
    print "TRANSLATE: table_name=[$table_name] src_id=[undef] tlt=[undef]\n";
    return undef;
  }

  # fetch all known translations, they are stored in the destionation's database
  my $t;
  unless (defined ($t= $ctx->{'tlt'}))
  {
    $t= $ctx->{'tlt'}= {};
    my $d= $ctx->{'dst'}->get_all_x ('syncs', [ 'sync_context_id=?', $ctx->{'ctx_id'} ] );
    # print "d: ", main::Dumper ($d);

    foreach my $id (keys %$d)
    {
      my $dd= $d->{$id};
      my ($tn, $si, $di, $st, $sd)= map { $dd->{$_} } qw(table_name src_id dst_id status sync_date);
      $t->{$tn}->{$si}= [ $di, $st, $sd ];
    }
  }

  if (exists ($t->{$table_name}->{$src_id}))
  {
    my $x= $t->{$table_name}->{$src_id};
    print "TRANSLATE: table_name=[$table_name] src_id=[$src_id] tlt=[",join(',',@$x),"]\n";
    return (wantarray) ? @$x : $x->[0];
  }

  return undef;
}

sub store_translate
{
  my $ctx= shift;
  my $table_name= shift;
  my $src_id= shift;
  my $dst_id= shift;

  my $dbh= $ctx->{'dst'}->connect();
  return undef unless (defined ($dbh));

  my $ssi= "INSERT INTO syncs (sync_context_id, table_name, src_id, dst_id, sync_date, status) VALUES (?,?,?,?,now(),2)";
  print "ssi=[$ssi]\n";
  my $sth= $dbh->prepare($ssi);
  my @vals= ($ctx->{'ctx_id'}, $table_name, $src_id, $dst_id);
  print "vals: ", join (',', @vals), "\n";
  $sth->execute(@vals);
  $sth->finish();
}

sub sync_project_users
{
  my $ctx= shift;
  my $sp_id= shift;
  my $dp_id= shift;

  my ($ctx_id, $src, $dst)= map { $ctx->{$_} } qw(ctx_id src dst);

  # pcx means something like "project context"; TODO: change that name if a better one comes up...
  my $s_pcx= $src->pcx_members ($sp_id);
  my $d_pcx= $dst->pcx_members ($dp_id);
  # print "keys src: ", join (' ', keys %$src), "\n";
  # print "pcx: ", main::Dumper ($pcx);

  my ($s_members, $s_users)= map { $s_pcx->{$_} } qw(members users);
  my ($d_members, $d_users)= map { $d_pcx->{$_} } qw(members users);

  # verbose Redmine::DB::MySQL (1);

  my @s_member_ids= (keys %$s_members);
  foreach my $s_member_id (@s_member_ids)
  {
    my $s_member=    $s_members->{$s_member_id};
    my $s_user_id=   $s_member->{'user_id'};
    my $s_user=      $s_users->{$s_user_id};
# next unless ($s_user->{'type'} eq 'Group');

    print "s_member: ", main::Dumper ($s_member);
    my $d_user_id= $ctx->sync_user ($s_user_id, $s_user);

    my ($d_member_id, $d_status, $d_sync_date)= $ctx->translate ('members', $s_member_id);
    print "s_member_id=[$s_member_id] d_member=[$d_member_id] d_status=[$d_status] d_sync_date=[$d_sync_date]\n";

    unless (defined ($d_member_id))
    {
      my $d_member=
      {
        'user_id' => $d_user_id,
        'project_id' => $dp_id,
        'created_on' => $s_member->{'created_on'},
        'mail_notification' => $s_member->{'mail_notification'},
      };

      $d_member_id= $dst->insert ('members', $d_member);
      $ctx->store_translate('members', $s_member_id, $d_member_id);
    }
  }

=begin comment

sync member_roles

mysql> desc member_roles;
+----------------+---------+------+-----+---------+----------------+
| Field          | Type    | Null | Key | Default | Extra          |
+----------------+---------+------+-----+---------+----------------+
| id             | int(11) | NO   | PRI | NULL    | auto_increment |
| member_id      | int(11) | NO   | MUL | NULL    |                |
| role_id        | int(11) | NO   | MUL | NULL    |                |
| inherited_from | int(11) | YES  |     | NULL    |                |
+----------------+---------+------+-----+---------+----------------+

inherited_from points back to member_roles.id and that record might not be synced when the current record is processed.

=end comment
=cut

  my $in= 'member_id IN ('. join(',', map { '?' } @s_member_ids) . ')';

  my $s_mr_hash= $src->get_all_x ('member_roles', [ $in, @s_member_ids ]);
  # print "s_mr_hash: ", main::Dumper ($s_mr_hash);
  my @s_mr_ids= sort { $a <=> $b } keys %$s_mr_hash; # maybe ordering helps
  print "s_mr_ids: [", join (',', @s_mr_ids), "]\n";
  print "\n\n", '='x72, "MEMBER_ROLE processing\n", '-'x72, "\n";
  MEMBER_ROLE: while (@s_mr_ids)
  {
    my $s_mr_id= shift @s_mr_ids;
    my $s_mr= $s_mr_hash->{$s_mr_id};
    print "member_role: ", main::Dumper ($s_mr);
    my $d_mr_id= $ctx->translate('member_roles', $s_mr_id);
    
    if (defined ($d_mr_id))
    { # this member_role was already synced, so we can skip it.
      print "member_role already synced: $s_mr_id -> $d_mr_id\n";
      next MEMBER_ROLE;
    }

    # if the role is not yet know, we need to pull it over
    my $s_role_id= $s_mr->{'role_id'};
    my $d_role_id= $ctx->translate ('roles', $s_role_id);
    $d_role_id= $ctx->sync_role ($s_role_id) unless (defined ($d_role_id));

    # users can inherit their roles from a group;
    # inherited_from is that group's id from the member_roles-table
    my $s_inh_from= $s_mr->{'inherited_from'};
    print "s_inh_from=[$s_inh_from] s_mr: ", main::Dumper ($s_mr);

    my $d_inh_from;
    if (defined ($s_inh_from))
    {
      $d_inh_from= $ctx->translate ('member_roles', $s_inh_from);
      unless (defined ($d_inh_from))
      {
        unshift (@s_mr_ids, $s_inh_from);
        print "QQQ: inherited_from member_record [$s_inh_from] not yet know, inserted at the head of the queue!\n";
        next MEMBER_ROLE;
      }
    }

    my $d_member_id= $ctx->translate ('members', $s_mr->{'member_id'});
    unless (defined ($d_member_id))
    {
      print "ATTN: member not yet synced! member_id=[", $s_mr->{'member_id'}, "]; skipping member_role!\n";
      next MEMBER_ROLE;
    }

    my %d_mr=
    (
      'member_id' => $d_member_id,
      'role_id' => $d_role_id,
    );
    $d_mr{'inherited_from'}= $d_inh_from if (defined ($d_inh_from));

    print "new member_role record: ", main::Dumper (\%d_mr);

    $d_mr_id= $ctx->{'dst'}->insert ('member_roles', \%d_mr);
    $ctx->store_translate('member_roles', $s_mr_id, $d_mr_id);
  }

}

sub sync_role
{
  my $ctx= shift;
  my $s_role_id= shift;

  my $res= $ctx->{'src'}->get_all_x ('roles', [ 'id=?', $s_role_id ]);
  return undef unless (defined ($res));
  print "sync_role: s_role_id=[$s_role_id] res: ", main::Dumper ($res);

  my $s_role= $res->{$s_role_id};
  my %d_role= %$s_role;
  delete ($d_role{'id'});

  my $d_role_id= $ctx->{'dst'}->insert ('roles', \%d_role);
  $ctx->store_translate('roles', $s_role_id, $d_role_id);

  $d_role_id;
}

sub sync_user
{
  my $ctx= shift;
  my $s_user_id= shift;
  my $s_user= shift;

  unless (defined ($s_user))
  {
    my $res= $ctx->{'src'}->get_all_x ('users', [ 'id=?', $s_user_id ]);
    return undef unless (defined ($res));

    $s_user= $res->{$s_user_id};
  }

    print "s_user: ", main::Dumper ($s_user);

    my ($d_user_id, $d_status, $d_sync_date)= $ctx->translate ('users', $s_user_id);
    print "s_user_id=[$s_user_id] d_user_id=[$d_user_id] d_status=[$d_status] d_sync_date=[$d_sync_date]\n";

    unless (defined ($d_user_id))
    {
      my $d_user= $ctx->clone_user ($s_user);
      print "cloned_user: ", main::Dumper ($d_user);

      $d_user_id= $ctx->{'dst'}->insert ('users', $d_user);
      $ctx->store_translate('users', $s_user_id, $d_user_id);
    }

  $d_user_id;
}

sub clone_user
{
  my $ctx= shift;
  my $src= shift;

  my %user= %$src;
  $user{'auth_source_id'}= $ctx->translate ('auth_sources', $src->{'auth_source_id'});
  delete($user{'id'});
  \%user;
}

sub sync_wiki
{

=begin comment

sync wiki
    # my $pcx= $src->pcx_wiki ($proj_id);

    # print "pcx: ", main::Dumper ($pcx);
    # print "src: ", main::Dumper ($src);

=end comment
=cut

}

1;

