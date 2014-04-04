
package Redmine::DB;

use strict;

sub new
{
  my $class= shift;
  my $self={};
  bless $self, $class;
  $self->set (@_);
  $self;
}

sub set
{
  my $self= shift;
  my %par= @_;
  foreach my $an (keys %par) { $self->{$an}= $par{$an}; }
}

1;

