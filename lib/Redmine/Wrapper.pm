
package Redmine::Wrapper;

use strict;

use WebService::Redmine;

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

  my $rm= new WebService::Redmine (%{$self->{'cfg'}->{'redmine'}});
  # print "rm: ", Dumper ($rm);
  $self->{_rm}= $rm;
}

sub fixup_issue
{
  my $self= shift;
  my $issue= shift;
  my $par= shift;

  foreach my $key (keys %$par)
  {
    if ($key eq 'custom_fields')
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
 
  print "ids: ", main::Dumper($ids);

  $issue->{custom_fields}= [] unless (defined ($issue->{custom_fields}));
  my $cf= $issue->{custom_fields};
  my %idx;
  for (my $i= 0; $i <= $#$cf; $i++)
  {
    my $cf_i= $cf->[$i];
    $idx{$cf_i->{'name'}}= $i;
  }
  print "cf: ", main::Dumper($cf);

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
      'id' => $ids->{$an},
      'name' => $an,
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

  print "issue: ", main::Dumper($issue);
}

1;

__END__

