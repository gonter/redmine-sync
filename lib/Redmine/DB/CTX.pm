
=head1 NAME

  Redmine::DB::CTX;

=head1 DESCRIPTION

This implements what I call a "Redmine synchronisation context".
It has a synchronisation context id (sync_context_id), a source (src)
and a destination (dst) which resemble database connections.  During
the synchronisation, this structure picks up a lot more of transient
information.

=head1 SYNOPSIS

  my $ctx= new Redmine::DB::CTX ('ctx_id' => $setup->{'sync_context_id'}, 'src' => $src, 'dst' => $dst);

=cut

package Redmine::DB::CTX;

use strict;
use parent 'Redmine::DB';

use Data::Dumper;

=head2 $context->sync_project ($source_project_id, $destination_project_id)

sync one project

=cut

sub sync_project
{
  my $ctx= shift;
  my $sp_id= shift;
  my $dp_id= shift;

  # $ctx->sync_project_members ($sp_id, $dp_id);
  # $ctx->sync_project_user_preferences ($sp_id, $dp_id);
  $ctx->sync_wiki ($sp_id, $dp_id);
}

=head1 TRANSLATION

Possibly the most important aspect of a synchronisation job is the
translation of record IDs.  This is done using a translation table called
`syncs` which is stored in the destinatios (dst) database.

The "CREATE TABLE" statements can be found in the source (here) or retrieved via

  my ($ddl_sync_contexts, $ddl_syncs)= Redmine::DB::CTX::get_DDL();

=cut

  my $TABLE_sync_contexts= <<'EOX';
CREATE TABLE `sync_contexts`
(
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(255) DEFAULT NULL,
  `description` longtext DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;
EOX
  
  my $TABLE_syncs= <<'EOX';
CREATE TABLE `syncs`
(
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `sync_context_id` int(11) DEFAULT NULL,
  `table_name` varchar(255) DEFAULT NULL,
  `src_id` int(11) DEFAULT NULL,
  `dst_id` int(11) DEFAULT NULL,
  `sync_date` datetime DEFAULT NULL,
  `status` int(4) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;
EOX

sub get_DDL { return ($TABLE_sync_contexts, $TABLE_syncs); }

=head2 $context->init_translation()

Read the known translation table for the give synchronisation context
and keep it around.

=cut

sub init_translation
{
  my $ctx= shift;

  # fetch all known translations, they are stored in the destionation's database
  my $t;
  unless (defined ($t= $ctx->{'tlt'}))
  {
    print "NOTE: loading syncs\n";
    $t= $ctx->{'tlt'}= {};
    my $d= $ctx->{'dst'}->get_all_x ('syncs', [ 'sync_context_id=?', $ctx->{'ctx_id'} ] );
    # print "d: ", Dumper ($d);

    foreach my $id (keys %$d)
    {
      my $dd= $d->{$id};
      my ($tn, $si, $di, $st, $sd)= map { $dd->{$_} } qw(table_name src_id dst_id status sync_date);
      $t->{$tn}->{$si}= [ $di, $st, $sd ];
    }
  }

  return $t;
}

=head2 $context->translate ($table_name, $src_id)

translate a table's id.  Takes the source's id and returns the
destination's id, if known or undef otherwise.

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

  my $t= $ctx->init_translation();
  if (exists ($t->{$table_name}->{$src_id}))
  {
    my $x= $t->{$table_name}->{$src_id};
    # TODO: if verbosity ...
    print "TRANSLATE: table_name=[$table_name] src_id=[$src_id] tlt=[",join(',',@$x),"]\n";
    return (wantarray) ? @$x : $x->[0];
  }
  print "TRANSLATE: table_name=[$table_name] src_id=[$src_id] tlt=undef\n";

  return undef;
}

=head2 $ctx->store_translation ($table_name, $src_id, $dst_id)

Update translation table in the database and in the cache.

=cut

sub store_translation
{
  my $ctx= shift;
  my $table_name= shift;
  my $src_id= shift;
  my $dst_id= shift;

  my $t= $ctx->init_translation();

  my $dbh= $ctx->{'dst'}->connect();
  return undef unless (defined ($dbh));

  # TODO: maybe we need to check if (sync_context_id, table_name, src_id)
  # are already present in the database.  Then we should update the
  # record!

  my $ssi= "INSERT INTO syncs (sync_context_id, table_name,
  src_id, dst_id, sync_date, status) VALUES (?,?,?,?,now(),2)";
  print "ssi=[$ssi]\n"; my $sth= $dbh->prepare($ssi); my @vals=
  ($ctx->{'ctx_id'}, $table_name, $src_id, $dst_id); print "vals: ",
  join (',', @vals), "\n"; $sth->execute(@vals); $sth->finish();

  $t->{$table_name}->{$src_id}= [ $dst_id, 2, undef ];
}

=head1 USERS

User-related tables are:

  (handled)
    users
    members
    member_roles

 (not yet handled)
    watchers (TODO: this also points to contents (tickets, wiki_pages, etc.), so this must wait)
    user_preferences

=head2 $context->sync_project_users ($source_project_id, $destination_project_id)

Synchronize the users and related tables.

=cut

sub sync_project_members
{
  my $ctx= shift;
  my $sp_id= shift;
  my $dp_id= shift;

  my ($src, $dst)= map { $ctx->{$_} } qw(src dst);

  # pcx means something like "project context"; TODO: change that name if a better one comes up...
  my $s_pcx= $src->pcx_members ($sp_id);
  my $d_pcx= $dst->pcx_members ($dp_id);
  # print "keys src: ", join (' ', keys %$src), "\n";
  # print "pcx: ", Dumper ($pcx);

  my ($s_members, $s_users)= map { $s_pcx->{$_} } qw(members users);
  my ($d_members, $d_users)= map { $d_pcx->{$_} } qw(members users);

=begin comment

TODO: A user might be already present on the destination Redmine instance,
this code would try to import him anyway.  We need a method to verify
that a user is already present, maybe some kind of logic like that
implemented in sync_project_user_preferences below.

For now, the operator would have to add the translations to the syncs
table by hand.  If users would be imported on a fresh instance, this
would not really be an issue.

=end comment
=cut

  # verbose Redmine::DB::MySQL (1);

  my @s_member_ids= (keys %$s_members);
  foreach my $s_member_id (@s_member_ids)
  {
    my $s_member=    $s_members->{$s_member_id};
    my $s_user_id=   $s_member->{'user_id'};
    my $s_user=      $s_users->{$s_user_id};
# next unless ($s_user->{'type'} eq 'Group');

    print "s_member: ", Dumper ($s_member);
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
      $ctx->store_translation('members', $s_member_id, $d_member_id);
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
  # print "s_mr_hash: ", Dumper ($s_mr_hash);
  my @s_mr_ids= sort { $a <=> $b } keys %$s_mr_hash; # maybe ordering helps
  print "s_mr_ids: [", join (',', @s_mr_ids), "]\n";
  print "\n\n", '='x72, "MEMBER_ROLE processing\n", '-'x72, "\n";
  MEMBER_ROLE: while (@s_mr_ids)
  {
    my $s_mr_id= shift @s_mr_ids;
    my $s_mr= $s_mr_hash->{$s_mr_id};
    print "member_role: ", Dumper ($s_mr);
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
    print "s_inh_from=[$s_inh_from] s_mr: ", Dumper ($s_mr);

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

    print "new member_role record: ", Dumper (\%d_mr);

    $d_mr_id= $ctx->{'dst'}->insert ('member_roles', \%d_mr);
    $ctx->store_translation('member_roles', $s_mr_id, $d_mr_id);
  }

}

sub sync_role
{
  my $ctx= shift;
  my $s_role_id= shift;

  my $res= $ctx->{'src'}->get_all_x ('roles', [ 'id=?', $s_role_id ]);
  return undef unless (defined ($res));
  print "sync_role: s_role_id=[$s_role_id] res: ", Dumper ($res);

  my $s_role= $res->{$s_role_id};
  my %d_role= %$s_role;
  delete ($d_role{'id'});

  my $d_role_id= $ctx->{'dst'}->insert ('roles', \%d_role);
  $ctx->store_translation('roles', $s_role_id, $d_role_id);

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

    print "s_user: ", Dumper ($s_user);

    my ($d_user_id, $d_status, $d_sync_date)= $ctx->translate ('users', $s_user_id);
    print "s_user_id=[$s_user_id] d_user_id=[$d_user_id] d_status=[$d_status] d_sync_date=[$d_sync_date]\n";

    unless (defined ($d_user_id))
    {
      my $d_user= $ctx->clone_user ($s_user);
      print "cloned_user: ", Dumper ($d_user);

      $d_user_id= $ctx->{'dst'}->insert ('users', $d_user);
      $ctx->store_translation('users', $s_user_id, $d_user_id);
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

=head2 $context->sync_project_user_preferences($source_project_id, $destination_project_id)

Sync preferences of users associated with a certain project.

=cut

sub sync_project_user_preferences
{
  my $ctx= shift;
  my $sp_id= shift;
  my $dp_id= shift;

  my ($src, $dst)= map { $ctx->{$_} } qw(src dst);
  my $st= $ctx->stats('user_preferences');

  my $s_pref= $src->get_all_x ('user_preferences', [ 'user_id in (select user_id from members where project_id=?)', $sp_id ]);
  my $s_up= reindex($s_pref, 'user_id');

  # first: retrieve a list of translated user_id values:
  my @s_uids= keys %$s_up;
  my %s_uids;
  my %d_uids; # user_id on destination with link to user_id on source and later a preference record on the source
  foreach my $s_uid (@s_uids)
  {
    my $d_uid= $ctx->translate ('users', $s_uid);
    # print "s_uid=[$s_uid] -> d_uid=[$d_uid]\n";
    $st->{'cnt'}++;

    if (defined ($d_uid))
    {
      $s_uids{$s_uid}= $d_uid;
      $d_uids{$d_uid}= [ $s_uid ]; # link back to the source
    }
    else
    { # not yet translated, maybe this user was not yet synced!
      # TODO: call sync method for this user
      # for now we assume that users were already synced
      print "ATTN: user_id on source ($s_uid) not translated; maybe the member synchronization must be rerun!\n";
      $st->{'missing'}++;
      push (@{$st->{'missing_uid'}}, $s_uid);
    }
  }

  # second: see if users with the translated user_id are already on the destination and link their preferences into %d_uids
  # print "user_id mapping: ", Dumper (\%s_uids);
  my @tlt_uids= map { $s_uids{$_} } keys %s_uids;
# verbose Redmine::DB::MySQL (1);
  my $d_pref= $dst->get_all_x ('user_preferences', [ 'user_id in ('.join(',',map { '?' } @tlt_uids).')', @tlt_uids ]);
  # print "translated preferences: ", Dumper ($d_pref);
  foreach my $d_id (keys %$d_pref)
  {
    my $x= $d_pref->{$d_id};
    $d_uids{$x->{'user_id'}}->[1]= $x;
  }

  # finally: see which users have a preferences record and store it for those who don't have one yet.
  foreach my $d_uid (keys %d_uids)
  {
    my $x= $d_uids{$d_uid};
    print '-'x72, "\n";
    print "d_uid=[$d_uid] ", Dumper ($x);

    if (defined ($x->[1]))
    {
      $st->{'unchanged'}++;
    }
    else
    { # no prefs record yet, copy it
      my %d_prefs= %{$s_up->{$x->[0]}};

      print "prefs on source: ", Dumper (\%d_prefs);

      my $s_prefs_id= delete ($d_prefs{'id'});
      $d_prefs{'user_id'}= $d_uid;

      print "save new prefs: ", Dumper (\%d_prefs);

      my $d_prefs_id= $dst->insert ('user_preferences', \%d_prefs);
      # NOTE: do we need the translation at all?  possibly not, but what the heck
      $ctx->store_translation('user_preferences', $s_prefs_id, $d_prefs_id);

      $st->{'copied'}++;
    }
  }

  $st;
}

sub sync_wiki
{
  my $ctx= shift;
  my $sp_id= shift;
  my $dp_id= shift;

  my ($src, $dst)= map { $ctx->{$_} } qw(src dst);
  # my $st= $ctx->stats('wiki'); each table has it's own counters

  my $s_pcx= $src->pcx_wiki($sp_id);
  print "s_pcx: (", join (',', sort keys %$s_pcx), ")\n";
  # print Dumper ($s_pcx); exit;

  # NOTE: Let's assume that the destination does not receive pages from
  # somewhere else (e.g. someone adding that by hand)
  $ctx->sync_generic_table ($s_pcx, 'wikis',          [ [ 'project_id' => 'projects' ] ]);
  $ctx->sync_generic_table ($s_pcx, 'wiki_pages',     [ [ 'wiki_id' => 'wikis' ], [ 'parent_id' => 'wiki_pages' ] ]);
  $ctx->sync_generic_table ($s_pcx, 'wiki_redirects', [ [ 'wiki_id' => 'wikis' ] ]);
  $ctx->sync_generic_table ($s_pcx, 'wiki_contents',  [ [ 'page_id' => 'wiki_pages' ], ['author_id' => 'users' ] ]);
  $ctx->sync_generic_table ($s_pcx, 'wiki_content_versions',  [ [ 'wiki_content_id' => 'wiki_contents'], [ 'page_id' => 'wiki_pages' ], ['author_id' => 'users' ] ]);
}

sub sync_generic_table
{
  my $ctx= shift;
  my $s_pcx= shift;
  my $table_name= shift;
  my $tlt= shift; # list pairs

  print '-'x72, "\n";
  print "sync_generic_table: table_name=[$table_name]\n";
  my $table= $s_pcx->{$table_name};
  # print "table [$table_name] ", Dumper ($table); exit;

  my $cnt= $ctx->stats($table_name);
  my @s_ids= sort { $a <=> $b} keys %$table; # maybe sorting helps to bring order into an hierarchy
  print "s_ids: ", join (',', @s_ids), "\n";
  ITEM: while (my $s_id= shift (@s_ids))
  {
    my $d_id= $ctx->translate ($table_name, $s_id);
    print "d_id=[$d_id]\n";
    $cnt->{'processed'}++;

    if (defined ($d_id))
    {
      $cnt->{'unchanged'}++;
    }
    else
    {
      my %data= %{$table->{$s_id}};
      delete ($data{'id'});

      # translate attributes (an) pointing to table (tn); $tlt is a list of pairs
      TLT: foreach my $t (@$tlt)
      {
        my ($an, $tn)= @$t;
        my $s_av= $data{$an};
        next TLT unless (defined ($s_av));
        my $d_av= $ctx->translate ($tn, $s_av);

        unless (defined ($d_av))
        {
          if ($tn eq $table_name)
          { # this is a self referential table, put the (yet unresolved) to the head of the queue
            # TODO: this could lead to an endless loop!
            unshift (@s_ids, $s_av);
            push (@s_ids, $s_id);
            next ITEM;
          }

          print "ERROR: translation not known for an=[$an] s_av=[$s_av] in table=[$tn]\n";
          $cnt->{'av_tlt_missing'}++;
          next TLT;
        }
        $data{$an}= $d_av;
      }

      $d_id= $ctx->{'dst'}->insert ($table_name, \%data);
      $ctx->store_translation($table_name, $s_id, $d_id);
      $cnt->{'added'}++;
    }
  }

  $cnt;
}

=head1 INTERNAL METHODS?

=cut

sub stats
{
  my $self= shift;
  my $what= shift;

  my $t= $self->{'stats'}->{$what};
     $t= $self->{'stats'}->{$what}= {} unless (defined ($t));
  # print "accessing stats=[$what]: ", Dumper($self);
  $t;
}

=head1 INTERNAL FUNCTIONS

=cut

sub reindex
{
  my $hash= shift;
  my $key= shift;

  my %res= map { my $x= $hash->{$_}; $x->{$key} => $x } keys %$hash;
  \%res;
}

1;

__END__

=head1 TODOs

=head2 statistics

  We need counters about unchanged, new and updated records.  Deleted records may also be necessary.

=end

