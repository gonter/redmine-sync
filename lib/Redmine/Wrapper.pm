
package Redmine::Wrapper;

use strict;

use WebService::Redmine;

sub get_project_info;
sub get_tracker_map;

my %automapping=
(
  'project_ids' => { automap => 1, object => 'project', info => \&get_project_info },
  'tracker_ids' => { automap => 1, object => 'tracker', map => \&get_tracker_map },
);

my %USER_NAMES= map { $_ => 1 } qw(assigned_to);

sub new
{
  my $class= shift;

  my $obj= {};
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

# TODO: attach or connect are not really good names
sub attach
{
  my $self= shift;

  return $self->{_rm} if (exists ($self->{_rm}));

  my $rm= new WebService::Redmine (%{$self->{'cfg'}});
  # print "rm: ", Dumper ($rm);
  $self->{_rm}= $rm;
}

sub get_mapped_id
{
  my $self= shift;
  my $map_name= shift;
  my $name= shift;

  my $cfg= $self->{'cfg'};
  # print "cfg: ", main::Dumper ($cfg);

  $map_name= 'user_ids' if (exists ($USER_NAMES{$map_name}));
  my $m= $self->{$map_name};
  if (!defined ($m) && exists ($cfg->{$map_name}))
  {
    $m= $self->{$map_name}= { %$m }; # copy from config
  }

  # print "map_name=[$map_name] name=[$name] m=", main::Dumper ($m);

  my $id;
  my $perform_lookup= 1;
  if (exists ($m->{$name}))
  {
    $id= $m->{$name};
    # print "ATTN: no id known for $map_name=[$name]\n";

=begin comment

    if (exists ($cfg->{automapping}) && $cfg->{automapping} >= 1)
    { # TODO: add an *optional* lookup ...
      $perform_lookup= 1;
    }

=end comment
=cut

  }
  else
  {
    # print "ATTN: no *map* named [$map_name] available\n";

=begin comment

    if (exists ($cfg->{automapping}) && $cfg->{automapping} >= 2)
    {
      $perform_lookup= 1;
    }

=end comment
=cut

  }

  if (!defined ($id) && $perform_lookup)
  {
    # print "map_name=[$map_name] id not found, perform_lookup=[$perform_lookup]\n";

    if (exists ($automapping{$map_name}))
    { # TODO: allow dynamically fetched maps, when the map name is valid, e.g. project_ids etc..
      my $automap= $automapping{$map_name};
      # print "NOTE: checking automap: ", main::Dumper ($automap);
      if (defined (my $c_i= $automap->{info}))
      {
        my $pi= &$c_i ($self, $name);
        # print "pi: ", main::Dumper ($pi);
        $id= $pi->{id} if (defined ($pi));
      }
      elsif (defined (my $c_m= $automap->{map}))
      {
        my $map= &$c_m ($self);
        # print "map: ", main::Dumper ($map);
        $id= $map->{$name} if (defined ($map));
      }
    }
  }

  $id;
}

sub get_tracker_id
{
  my $self= shift;
  my $tracker_name= shift;

  $self->get_mapped_id ('tracker_ids', $tracker_name);
}

# Note: for some reason, receiving info for one tracker is not possible
sub get_tracker_map
{
  my $self= shift;

  my $rm= $self->attach();
  my $tracker_list= $rm->trackers();
  # print __LINE__, " tracker_list: ", main::Dumper ($tracker_list);

  my %trackers;
  if (defined ($tracker_list))
  {
    %trackers= map { $_->{name} => $_->{id} } @{$tracker_list->{trackers}};
    $self->{tracker_ids}= \%trackers;
  }

  \%trackers;
}

sub get_project_id
{
  my $self= shift;
  my $project_name= shift;

  $self->get_mapped_id ('project_ids', $project_name);
}

sub get_project_info
{
  my $self= shift;
  my $name= shift;

  my $rm= $self->attach();
  my $proj= $rm->project( $name );

  return undef unless (defined ($proj));

  # print __LINE__, " get_project_info: name=[$name] proj: ", main::Dumper ($proj);
  return $proj->{'project'};
}

sub fixup_issue
{
  my $self= shift;
  my $issue= shift;
  my $par= shift;

  foreach my $cf_name (keys %$par)
  {
    if ($cf_name eq 'custom_fields')
    {
      transcribe_custom_fields ($self->{'cfg'}->{'custom_field_ids'}, $issue, $par->{'custom_fields'});
    }
  }
}

=head1 INTERNAL FUNCTIONS

=head2 transcribe_custom_fields ($custom_field_id_mapping_table, $issue, $key_value_hashref)

transcribe custom fields from a simple key/value list in
$key_value_hashref into a hash_ref representing an issue
($issue) using a mapping table for custom field ids stored in
$custom_filed_id_mapping_table.

=cut

sub transcribe_custom_fields
{
  my $ids= shift;
  my $issue= shift;
  my $kv= shift;
 
  # print "ids: ", main::Dumper($ids);

  $issue->{custom_fields}= [] unless (defined ($issue->{custom_fields}));
  my $cf= $issue->{custom_fields};
  my %idx;
  for (my $i= 0; $i <= $#$cf; $i++)
  {
    my $cf_i= $cf->[$i];
    $idx{$cf_i->{'name'}}= $i;
  }
  # print "cf: ", main::Dumper($cf);

  # update incoming custom fields
  AN: foreach my $an (keys %$kv)
  {
    unless (exists ($ids->{$an}))
    {
      print "an=[$an] not present in id mapping table\n";
      next AN;
    }

    my $new_val=
    {
      'value' => $kv->{$an},
      'id'    => $ids->{$an},
      'name'  => $an,
    };

    if (exists ($idx{$an}))
    {
      $cf->[$idx{$an}]= $new_val;
    }
    else
    {
      push (@$cf, $new_val); # TODO: maybe we should update %idx here as well
    }
  }

  # print "issue: ", main::Dumper($issue);
}

1;

__END__

