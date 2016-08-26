
package Redmine::Wrapper;

use strict;

use WebService::Redmine;

my %automapping=
(
  'project_ids' => 1,
);

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

  my $c= $self->{'cfg'};
  # print "cfg: ", main::Dumper ($c);
  my $m= $c->{$map_name.'_ids'};

  # print "map_name=[$map_name] name=[$name] m=", main::Dumper ($m);

  my $id;
  my $perform_lookup= 0;
  if (exists ($m->{$name}))
  {
    $id= $m->{$name};
    print "ATTN: no id known for $map_name=[$name]\n";

    if (exists ($self->{automapping}) && $self->{automapping} >= 1)
    { # TODO: add an *optional* lookup ...
      $perform_lookup= 1;
    }
  }
  else
  {
    print "ATTN: no *map* named [$map_name] available\n";
    if (exists ($self->{automapping}) && $self->{automapping} >= 2 && exists ($automapping{$map_name}))
    { # TODO: allow dynamically fetched maps, when the map name is valied, e.g. project_ids etc..
      if ($name eq 'project')
      {
        my $pi= $self->get_project_info ($name);
        $perform_lookup= 1 if (defined ($pi));
      }
    }
  }

  if (!defined ($id) && $perform_lookup)
  {
  }

  $id;
}

sub get_tracker_id
{
  my $self= shift;
  my $tracker_name= shift;

  $self->get_mapped_id ('tracker_ids', $tracker_name);
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
  print __LINE__, " get_project_info: name=[$name] proj: ", main::Dumper ($proj);
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

