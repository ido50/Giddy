package Giddy::Cursor;

use Any::Moose;
use Carp;
use Try::Tiny;
use YAML::Any;

has 'count' => (is => 'ro', isa => 'Int', default => 0, writer => '_set_count');

has '_results' => (is => 'ro', isa => 'ArrayRef[HashRef]', writer => '_set_results', predicate => '_has_results');

has '_query' => (is => 'ro', isa => 'HashRef', required => 1);

has '_loc' => (is => 'ro', isa => 'Int', default => 0, writer => '_set_loc');

has '_loaded_results' => (is => 'ro', isa => 'HashRef', predicate => '_has_loaded', writer => '_set_loaded_results');

=head1 OBJECT METHODS

=head2 all()

=cut

sub all {
	my $self = shift;
	my @results;
	while ($self->has_next) {
		push(@results, $self->next);
	}
	return @results;
}

sub has_next {
	$_[0]->_loc < $_[0]->count;
}

sub next {
	my $self = shift;

	return unless $self->has_next;

	my $next = $self->_load_result($self->_results->[$self->_loc]);
	$self->_inc_loc;
	return $next;
}

sub rewind {
	$_[0]->_set_loc(0);
}

sub first {
	my $self = shift;

	return unless $self->count;

	return $self->_load_result($self->_results->[0]);
}

sub last {
	my $self = shift;

	return unless $self->count;

	return $self->_load_result($self->_results->[$self->count - 1]);
}

=head1 INTERNAL METHODS

=cut

sub _add_result {
	my ($self, $res) = @_;

	my @results = @{$self->_results || []};
	push(@results, $res);
	$self->_set_results(\@results);
	$self->_inc_count;
}

sub _inc_count {
	my $self = shift;

	$self->_set_count($self->count + 1);
}

sub _inc_loc {
	my $self = shift;

	$self->_set_loc($self->_loc + 1);
}

sub _load_result {
	my ($self, $result) = @_;

	if ($result->{article}) {
		return $self->_query->{coll}->_load_article($result->{article}, $self->_query->{opts}->{working});
	} elsif ($result->{document}) {
		return $self->_query->{coll}->_load_document($result->{document}, $self->_query->{opts}->{working});
	}
}

__PACKAGE__->meta->make_immutable;
